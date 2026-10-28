# terraform

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.6 |
| <a name="requirement_azapi"></a> [azapi](#requirement\_azapi) | ~> 2.0 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | ~> 5.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | >= 3.3.2 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_azapi"></a> [azapi](#provider\_azapi) | ~> 2.0 |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | ~> 5.0 |
| <a name="provider_random"></a> [random](#provider\_random) | >= 3.3.2 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_naming"></a> [naming](#module\_naming) | Azure/naming/azurerm | ~> 0.4 |

## Resources

| Name | Type |
| ---- | ---- |
| [azapi_resource.aspire_dashboard](https://registry.terraform.io/providers/Azure/azapi/latest/docs/resources/resource) | resource |
| [azapi_resource.event_table](https://registry.terraform.io/providers/Azure/azapi/latest/docs/resources/resource) | resource |
| [azurerm_application_insights.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/application_insights) | resource |
| [azurerm_consumption_budget_resource_group.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/consumption_budget_resource_group) | resource |
| [azurerm_container_app_environment.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/container_app_environment) | resource |
| [azurerm_log_analytics_workspace.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/log_analytics_workspace) | resource |
| [azurerm_monitor_action_group.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_action_group) | resource |
| [azurerm_monitor_data_collection_endpoint.events](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_data_collection_endpoint) | resource |
| [azurerm_monitor_data_collection_rule.events](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_data_collection_rule) | resource |
| [azurerm_monitor_diagnostic_setting.http_logs](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_diagnostic_setting) | resource |
| [azurerm_monitor_scheduled_query_rules_alert_v2.app_error](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_scheduled_query_rules_alert_v2) | resource |
| [azurerm_monitor_scheduled_query_rules_alert_v2.log_quota](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_scheduled_query_rules_alert_v2) | resource |
| [azurerm_monitor_scheduled_query_rules_alert_v2.workload_crashed](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_scheduled_query_rules_alert_v2) | resource |
| [azurerm_postgresql_flexible_server.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/postgresql_flexible_server) | resource |
| [azurerm_postgresql_flexible_server_active_directory_administrator.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/postgresql_flexible_server_active_directory_administrator) | resource |
| [azurerm_postgresql_flexible_server_database.grafana](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/postgresql_flexible_server_database) | resource |
| [azurerm_postgresql_flexible_server_firewall_rule.allow_azure_services](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/postgresql_flexible_server_firewall_rule) | resource |
| [azurerm_resource_group.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_group) | resource |
| [random_password.postgres_admin](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [azurerm_client_config.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/client_config) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_alert_email_address"></a> [alert\_email\_address](#input\_alert\_email\_address) | Address added to the alert action group as an email receiver, alongside the ARM role receiver that reaches whoever holds `Owner` on the subscription. Committed deliberately: this repository is public, so an address here is permanent in its history — an address is an identifier rather than a credential. Set it empty to send to the Owner role alone, or override with `TF_VAR_alert_email_address` to keep a different address out of git. | `string` | `"withersj888@outlook.com"` | no |
| <a name="input_budget_start_date"></a> [budget\_start\_date](#input\_budget\_start\_date) | First day of the budget's first period, which Azure requires to be the first of a month. Ignored after creation — see the `lifecycle` block in `main.alerts.tf` — so it only matters on a fresh apply, and a date in an already-past month is rejected on create. | `string` | `"2026-09-01T00:00:00Z"` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Deployment environment. Drives resource naming, and is part of the environment name tenants resolve by. | `string` | n/a | yes |
| <a name="input_location"></a> [location](#input\_location) | Azure region resources are created in. Every tenant workload must be in this same region. | `string` | `"northeurope"` | no |
| <a name="input_monthly_budget_amount"></a> [monthly\_budget\_amount](#input\_monthly\_budget\_amount) | Monthly Azure spend, in the subscription's billing currency, above which the budget notifies. The shared Postgres server is the only standing cost here (B1ms, about 13-17 a month); everything else is still Consumption-only and inside the Log Analytics free grant. The default sits just above the server, so it notices a mistake (a workload profile attached by hand, a tenant's runaway logging, a second server) rather than firing every month. Notifications only: Azure budgets never stop anything spending. | `number` | `25` | no |
| <a name="input_postgres_sku_name"></a> [postgres\_sku\_name](#input\_postgres\_sku\_name) | Compute SKU of the shared Postgres server. Burstable B1ms is the smallest Flexible Server offers; there is no serverless or auto-pause tier, so this bills per hour for as long as the server exists. | `string` | `"B_Standard_B1ms"` | no |
| <a name="input_postgres_storage_mb"></a> [postgres\_storage\_mb](#input\_postgres\_storage\_mb) | Provisioned storage. Billed on this figure rather than bytes used, and it can never be reduced, only grown, so it sits at Azure's 32 GB minimum. | `number` | `32768` | no |
| <a name="input_postgres_storage_tier"></a> [postgres\_storage\_tier](#input\_postgres\_storage\_tier) | Storage performance tier. P4 is the default for 32 GB; a higher tier raises the monthly bill for IOPS no tenant here needs. | `string` | `"P4"` | no |
| <a name="input_postgres_version"></a> [postgres\_version](#input\_postgres\_version) | Major PostgreSQL version of the shared server. Matches market-agent's, so its data moves by dump and restore without a version change on the way. | `string` | `"17"` | no |
| <a name="input_postgres_zone"></a> [postgres\_zone](#input\_postgres\_zone) | Availability zone the server is placed in. northeurope offers 1, 2 and 3 for B1ms. | `string` | `"1"` | no |
| <a name="input_project_name"></a> [project\_name](#input\_project\_name) | Name included in every resource name here. Tenants resolve the Container Apps environment by name (`cae-<project_name>-<environment>`), so changing this after tenants exist means updating each of them — treat it as fixed once anything has deployed. | `string` | `"platform"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to all resources, merged with (and taking precedence over) the default tags (`environment`, `managed-by`). | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_app_insights_connection_string"></a> [app\_insights\_connection\_string](#output\_app\_insights\_connection\_string) | Application Insights connection string, which tenant workloads receive as `APPLICATIONINSIGHTS_CONNECTION_STRING`. Tenants normally read this from their own `azurerm_application_insights` data source rather than from here. |
| <a name="output_app_insights_name"></a> [app\_insights\_name](#output\_app\_insights\_name) | Application Insights name, for a tenant's data source. |
| <a name="output_container_app_environment_id"></a> [container\_app\_environment\_id](#output\_container\_app\_environment\_id) | ARM ID of the shared Container Apps environment, for a tenant that would rather pass the ID directly than resolve it by name. |
| <a name="output_container_app_environment_name"></a> [container\_app\_environment\_name](#output\_container\_app\_environment\_name) | Name of the shared Container Apps environment. This plus `resource_group_name` is what a tenant needs to resolve it. |
| <a name="output_events_dcr_id"></a> [events\_dcr\_id](#output\_events\_dcr\_id) | ARM ID of the events data collection rule: the scope github-repos grants `Monitoring Metrics Publisher` on, for each identity allowed to send. |
| <a name="output_events_dcr_immutable_id"></a> [events\_dcr\_immutable\_id](#output\_events\_dcr\_immutable\_id) | Immutable ID of the events data collection rule, the part of the ingestion URL that names the rule. Set alongside the endpoint as `EVENTS_DCR_IMMUTABLE_ID`. |
| <a name="output_events_ingestion_endpoint"></a> [events\_ingestion\_endpoint](#output\_events\_ingestion\_endpoint) | Logs Ingestion endpoint for `Deployments_CL` and `OpsEvents_CL`. github-repos sets it on every app repo's dev environment as `EVENTS_INGESTION_ENDPOINT`, which the shared deploy workflow posts to. |
| <a name="output_location"></a> [location](#output\_location) | Region the environment is in. A tenant's container apps and jobs may live in another resource group but must be in this region. |
| <a name="output_log_analytics_workspace_id"></a> [log\_analytics\_workspace\_id](#output\_log\_analytics\_workspace\_id) | Workspace ID, for a tenant adding a diagnostic setting on a resource of its own. |
| <a name="output_postgres_fqdn"></a> [postgres\_fqdn](#output\_postgres\_fqdn) | Host tenants connect to. Each tenant has its own database and login on it. |
| <a name="output_postgres_server_name"></a> [postgres\_server\_name](#output\_postgres\_server\_name) | Name of the shared Postgres server. It carries a random suffix (see main.database.tf), so tenants take it from here rather than deriving it. |
| <a name="output_resource_group_name"></a> [resource\_group\_name](#output\_resource\_group\_name) | Resource group holding the shared environment and workspace. Tenants pass this as the resource group of their environment data source; their own resources live in their own group. |
<!-- END_TF_DOCS -->
