# One workspace and one Application Insights for every tenant. Sharing them is
# what makes a single job-failure alert able to cover workloads this
# configuration has never heard of, and it keeps all ingestion inside one
# 5 GB/month free grant rather than splitting the grant per project.
resource "azurerm_log_analytics_workspace" "this" {
  name                = module.naming.log_analytics_workspace.name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  sku                 = "PerGB2018"

  # 30 days is both the provider minimum and free (31 are included).
  retention_in_days = 30

  # See locals.observability.tf for why this figure, and for the consequence of
  # it now being shared.
  daily_quota_gb = local.log_daily_quota_gb

  tags = local.tags
}

resource "azurerm_application_insights" "this" {
  name                = module.naming.application_insights.name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  application_type    = "web"
  workspace_id        = azurerm_log_analytics_workspace.this.id

  # Defaults to 100 GB/day.
  daily_data_cap_in_gb = 0.1

  tags = local.tags
}

# There is deliberately **no** diagnostic setting on the Container Apps
# environment: it already ships console and system logs to this workspace via
# `log_analytics_workspace_id`, and a diagnostic setting would ingest the same
# lines a second time against a shared 0.15 GB/day cap.
#
# `AllMetrics` is off everywhere for a related reason — metrics are already in
# the platform metric store, free to query, and routing them here would pay to
# store a second copy.
#
# Tenant resources (a Key Vault, a database) are the tenant's to instrument,
# against this workspace's ID, which is published as an output.
