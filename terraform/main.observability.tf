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

# There is deliberately **no** diagnostic setting for console or system logs:
# the environment already ships those to this workspace via
# `log_analytics_workspace_id`, and a diagnostic setting for the same
# categories would ingest each line a second time against the shared
# 0.15 GB/day cap.
#
# HTTP logs are the one exception, and the reason is that they are not shipped
# any other way: `ContainerAppHTTPLogs` (ingress-layer request/response data —
# method, path, status code) only exists via a diagnostic setting, so scoping
# this one to that single category adds genuinely new data rather than a
# second copy of something already flowing. See main.alerts.tf for what reads
# it. It bills per request rather than per error, unlike the job-failure
# query below, so a tenant with real traffic volume is the one case that could
# meaningfully move the needle on the shared cap — worth knowing before a
# high-traffic tenant joins.
resource "azurerm_monitor_diagnostic_setting" "http_logs" {
  name                       = module.naming.monitor_diagnostic_setting.name
  target_resource_id         = azurerm_container_app_environment.this.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category = "ContainerAppHTTPLogs"
  }
}

# `AllMetrics` is off everywhere for a related reason — metrics are already in
# the platform metric store, free to query, and routing them here would pay to
# store a second copy.
#
# Tenant resources (a Key Vault, a database) are the tenant's to instrument,
# against this workspace's ID, which is published as an output.
