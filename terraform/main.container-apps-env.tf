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
