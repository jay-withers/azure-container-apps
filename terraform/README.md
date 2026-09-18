# terraform

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.6 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | ~> 5.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | >= 3.3.2 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | 5.6.0 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_naming"></a> [naming](#module\_naming) | Azure/naming/azurerm | ~> 0.4 |

## Resources

| Name | Type |
| ---- | ---- |
| [azurerm_application_insights.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/application_insights) | resource |
| [azurerm_consumption_budget_resource_group.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/consumption_budget_resource_group) | resource |
| [azurerm_container_app_environment.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/container_app_environment) | resource |
| [azurerm_log_analytics_workspace.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/log_analytics_workspace) | resource |
| [azurerm_monitor_action_group.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_action_group) | resource |
| [azurerm_monitor_scheduled_query_rules_alert_v2.job_failed](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_scheduled_query_rules_alert_v2) | resource |
| [azurerm_monitor_scheduled_query_rules_alert_v2.log_quota](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_scheduled_query_rules_alert_v2) | resource |
| [azurerm_resource_group.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_group) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_alert_email_address"></a> [alert\_email\_address](#input\_alert\_email\_address) | Address added to the alert action group as an email receiver, alongside the ARM role receiver that reaches whoever holds `Owner` on the subscription. Committed deliberately: this repository is public, so an address here is permanent in its history — an address is an identifier rather than a credential. Set it empty to send to the Owner role alone, or override with `TF_VAR_alert_email_address` to keep a different address out of git. | `string` | `"withersj888@outlook.com"` | no |
| <a name="input_budget_start_date"></a> [budget\_start\_date](#input\_budget\_start\_date) | First day of the budget's first period, which Azure requires to be the first of a month. Ignored after creation — see the `lifecycle` block in `main.alerts.tf` — so it only matters on a fresh apply, and a date in an already-past month is rejected on create. | `string` | `"2026-09-01T00:00:00Z"` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Deployment environment. Drives resource naming, and is part of the environment name tenants resolve by. | `string` | n/a | yes |
| <a name="input_location"></a> [location](#input\_location) | Azure region resources are created in. Every tenant workload must be in this same region. | `string` | `"northeurope"` | no |
| <a name="input_monthly_budget_amount"></a> [monthly\_budget\_amount](#input\_monthly\_budget\_amount) | Monthly Azure spend, in the subscription's billing currency, above which the budget notifies. This configuration has no standing cost at all — no database, no workload profile, and everything inside the Log Analytics free grant — so the default is a low ceiling chosen to notice a mistake (a workload profile attached by hand, a tenant's runaway logging) rather than to accommodate normal operation. Notifications only: Azure budgets never stop anything spending. | `number` | `5` | no |
| <a name="input_project_name"></a> [project\_name](#input\_project\_name) | Name included in every resource name here. Tenants resolve the Container Apps environment by name (`cae-<project_name>-<environment>`), so changing this after tenants exist means updating each of them — treat it as fixed once anything has deployed. | `string` | `"platform"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to all resources, merged with (and taking precedence over) the default tags (`environment`, `managed-by`). | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_app_insights_connection_string"></a> [app\_insights\_connection\_string](#output\_app\_insights\_connection\_string) | Application Insights connection string, which tenant workloads receive as `APPLICATIONINSIGHTS_CONNECTION_STRING`. Tenants normally read this from their own `azurerm_application_insights` data source rather than from here. |
| <a name="output_app_insights_name"></a> [app\_insights\_name](#output\_app\_insights\_name) | Application Insights name, for a tenant's data source. |
| <a name="output_container_app_environment_id"></a> [container\_app\_environment\_id](#output\_container\_app\_environment\_id) | ARM ID of the shared Container Apps environment, for a tenant that would rather pass the ID directly than resolve it by name. |
| <a name="output_container_app_environment_name"></a> [container\_app\_environment\_name](#output\_container\_app\_environment\_name) | Name of the shared Container Apps environment. This plus `resource_group_name` is what a tenant needs to resolve it. |
| <a name="output_location"></a> [location](#output\_location) | Region the environment is in. A tenant's container apps and jobs may live in another resource group but must be in this region. |
| <a name="output_log_analytics_workspace_id"></a> [log\_analytics\_workspace\_id](#output\_log\_analytics\_workspace\_id) | Workspace ID, for a tenant adding a diagnostic setting on a resource of its own. |
| <a name="output_resource_group_name"></a> [resource\_group\_name](#output\_resource\_group\_name) | Resource group holding the shared environment and workspace. Tenants pass this as the resource group of their environment data source; their own resources live in their own group. |
<!-- END_TF_DOCS -->
