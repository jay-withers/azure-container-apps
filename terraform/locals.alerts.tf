locals {
  # `Azure/naming/azurerm` has a single monitor_scheduled_query_rules_alert
  # token and this configuration needs two rules, so both are named by hand from
  # one prefix rather than by the module.
  alert_name_prefix = "${var.project_name}-${var.environment}"
}
