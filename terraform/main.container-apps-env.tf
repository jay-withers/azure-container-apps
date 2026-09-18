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

  # No workload_profile block on purpose, and this is the single most important
  # cost decision here: a workload profile carries a standing per-hour charge
  # whether or not anything runs. Consumption-only is what lets tenant apps
  # scale to zero and tenant jobs bill only for the seconds they execute, which
  # is what makes a shared environment free to leave sitting there.
  tags = local.tags
}
