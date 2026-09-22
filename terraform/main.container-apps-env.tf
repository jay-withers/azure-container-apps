# The shared environment. This is the whole point of the repository: one
# environment that every project deploys its container apps and jobs onto,
# rather than one per project.
#
# Tenants reference it by ID, resolved from this name and resource group with a
# `data "azurerm_container_app_environment"` source — see the README. A tenant's
# workload may live in its own resource group, but **must** be in the same
# region as this environment.
resource "azurerm_container_app_environment" "this" {
  name                       = module.naming.container_app_environment.name
  resource_group_name        = azurerm_resource_group.this.name
  location                   = azurerm_resource_group.this.location
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  # Inferred from the workspace in azurerm 4.x, but reverts to an "" default in
  # 5.x, which would then show as a perpetual diff.
  logs_destination = "log-analytics"

  # This is the `Consumption` profile, not a `Dedicated` one — still the single
  # most important cost decision here, just now spelled out rather than implied
  # by omission. Every environment now gets a `Consumption` workload profile
  # back from the API regardless of what's declared (verified against
  # cae-platform-dev on 2026-09-23: `az containerapp env workload-profile list`
  # returns it with no node count or SKU, unlike a real Dedicated profile),
  # which is Azure's own scale-to-zero, pay-per-second tier and carries no
  # standing charge. Leaving the block out entirely used to work, but now shows
  # as a permanent diff on every plan since Terraform has nothing to compare
  # the API's response against. Declaring it explicitly — and never adding a
  # second, `Dedicated` profile next to it — is what actually keeps the cost
  # promise; the trade-off to raise before ever changing `workload_profile_type`
  # is the one stated above, not whether this block exists.
  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
    minimum_count         = 0
    maximum_count         = 0
  }

  tags = local.tags
}

# The Aspire Dashboard: a live view (traces/metrics/logs/console) over every
# app on the shared environment, at https://aspire-dashboard.ext.<default
# domain>. It has no cost of its own — it reads the OTLP data container apps
# already emit rather than ingesting anything into the workspace — so it sits
# outside the "no diagnostic setting" and daily-cap concerns above.
#
# `azapi_resource` rather than `azurerm_container_app_environment_dotnet_
# component`: no such azurerm resource exists yet (see versions.tf). The name
# "aspire-dashboard" matches `az containerapp env dotnet-component create`'s
# default and the component already enabled by hand on this environment, which
# this resource is written to adopt via import rather than replace.
resource "azapi_resource" "aspire_dashboard" {
  # Newest version the installed azapi provider's embedded schema recognizes;
  # ARM itself has since moved on to a GA (non-preview) version, but bumping
  # this is a `terraform init -upgrade` away once azapi catches up.
  type      = "Microsoft.App/managedEnvironments/dotNetComponents@2025-10-02-preview"
  name      = "aspire-dashboard"
  parent_id = azurerm_container_app_environment.this.id

  body = {
    properties = {
      componentType = "AspireDashboard"
    }
  }
}
