locals {
  # The built-in Owner role's definition GUID, which is the same in every Azure
  # tenant. Hardcoded rather than looked up: an `azurerm_role_definition` data
  # source would make `plan` need directory reads for a constant.
  owner_role_definition_id = "8e3af657-a8ff-443c-a75c-2fe8c4bcb635"

  # `Azure/naming/azurerm` has a single monitor_scheduled_query_rules_alert
  # token and this configuration needs two rules, so both are named by hand from
  # one prefix rather than by the module.
  alert_name_prefix = "${var.project_name}-${var.environment}"
}
