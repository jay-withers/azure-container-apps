# One PostgreSQL Flexible Server for every tenant, each with its own database
# and its own login. It replaces a server per project per environment: B1ms has
# no serverless or auto-pause tier, so every server bills ~£13/month for as long
# as it exists, and market-agent alone would have needed three.
#
# **This is the one resource here that bills while idle**, and it was decided
# with that cost known (the observability plan's "consolidate Postgres"
# decision). Everything else in this configuration still costs nothing at rest.
#
# The server is shared; the *databases and logins* are still each tenant's.
# Grafana's database is created here because nothing else needs to exist
# first. market-agent moves onto this server by dump and restore, following
# the plan's runbook, not by changing its Terraform to point here.
#
# Same shape as market-agent's server (main.database.tf there), which is why
# Flexible Server rather than Azure SQL: Azure SQL is blocked in every region
# the `allowed-locations-dev` policy permits, and PostgreSQL is restricted in
# westeurope but open in northeurope — the region this whole platform is in.
resource "azurerm_postgresql_flexible_server" "this" {
  # checkov:skip=CKV_AZURE_136: geo-redundant backup doubles backup storage cost and cannot be
  #   changed after creation; nothing stored here is irreplaceable enough to justify it.
  # checkov:skip=CKV2_AZURE_57: no private endpoint. It is a standing cost and there is no VNet
  #   to attach it to, because the environment is Consumption-only. See the firewall rule below.
  #
  # `name_unique`, unlike everything else here: a server's name is its public
  # DNS label, unique across all of Azure, and `psql-platform-dev` is generic
  # enough to be taken. Tenants never resolve it by data source; they read the
  # FQDN from `make outputs` into their own configuration.
  name                = module.naming.postgresql_server.name_unique
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  version             = var.postgres_version

  sku_name = var.postgres_sku_name

  # Storage can never be reduced, only grown, and it bills the provisioned
  # figure rather than bytes used, so auto-grow stays off: left on, a runaway
  # table silently and permanently raises the floor.
  storage_mb        = var.postgres_storage_mb
  storage_tier      = var.postgres_storage_tier
  auto_grow_enabled = false

  backup_retention_days        = 7
  geo_redundant_backup_enabled = false

  public_network_access_enabled = true

  # Entra for every tenant workload and every human. Password auth is on for
  # one reason only: Grafana's own database connection cannot use an Entra
  # token, so its `grafana` role logs in with a password kept in the
  # observability repo's Key Vault. No other role is ever given a password.
  #
  # Azure requires an administrator login once password auth is on. Its
  # password exists only in this state and is never output: the Entra
  # administrator below is the one anyone actually uses.
  authentication {
    active_directory_auth_enabled = true
    password_auth_enabled         = true
    tenant_id                     = data.azurerm_client_config.current.tenant_id
  }
  administrator_login    = "pgadmin"
  administrator_password = random_password.postgres_admin.result

  zone = var.postgres_zone

  tags = local.tags

  lifecycle {
    # Azure fills this in itself when omitted, and reports a value that differs
    # from an empty config on the next plan.
    ignore_changes = [zone]

    # Every tenant's data lives here. Removing the server takes a deliberate
    # two-step change, never a stray plan.
    prevent_destroy = true
  }
}

# prevent_destroy only guards against this configuration; the lock also stops a
# portal click or a CLI delete, and covers everything inside the server. The
# pipeline can create it (github-repos' Resource Lock Creator role) but not
# remove it: that is github-repos' manual-remove-lock workflow, run by hand.
# While it stands, deleting anything in the server through Azure Resource Manager
# fails too, databases included.
resource "azurerm_management_lock" "server" {
  name       = "lock-${azurerm_postgresql_flexible_server.this.name}"
  scope      = azurerm_postgresql_flexible_server.this.id
  lock_level = "CanNotDelete"
  notes      = "Shared Postgres: every tenant database lives here. Remove with github-repos' manual-remove-lock."
}

resource "random_password" "postgres_admin" {
  length  = 40
  special = false
}

# From a variable rather than the deploying principal, so an apply from
# cd-terraform never makes the OIDC identity the administrator and locks every
# human out. Same principal as market-agent's server.
resource "azurerm_postgresql_flexible_server_active_directory_administrator" "this" {
  server_name         = azurerm_postgresql_flexible_server.this.name
  resource_group_name = azurerm_resource_group.this.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  object_id           = var.postgres_entra_administrator.object_id
  principal_name      = var.postgres_entra_administrator.principal_name
  principal_type      = "User"
}

resource "azurerm_postgresql_flexible_server_database" "grafana" {
  name      = "grafana"
  server_id = azurerm_postgresql_flexible_server.this.id
  charset   = "UTF8"
  collation = "en_US.utf8"

  lifecycle {
    prevent_destroy = true
  }
}

# 0.0.0.0-0.0.0.0 is Azure's sentinel for "allow other Azure services", which is
# what lets container apps reach the server without a VNet. It is every Azure
# customer, not just this subscription: a Consumption-only environment has no
# static egress IP to allow instead. Authentication is the real control —
# Entra for everything but Grafana's one password-holding role.
resource "azurerm_postgresql_flexible_server_firewall_rule" "allow_azure_services" {
  # checkov:skip=CKV2_AZURE_26: the sentinel described above grants reachability, not access.
  name             = "AllowAllAzureIps"
  server_id        = azurerm_postgresql_flexible_server.this.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}
