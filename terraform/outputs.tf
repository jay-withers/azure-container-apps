# These are the platform's contract with its tenants. A tenant resolves the
# environment with a `data "azurerm_container_app_environment"` source keyed on
# the name and resource group below, rather than reading this state — no shared
# credentials, and the coupling stays a convention rather than a lock.
#
# The values are stable by construction: `.name` is used throughout rather than
# `.name_unique`, so there is no random suffix to look up.

output "resource_group_name" {
  description = "Resource group holding the shared environment and workspace. Tenants pass this as the resource group of their environment data source; their own resources live in their own group."
  value       = azurerm_resource_group.this.name
}

output "container_app_environment_name" {
  description = "Name of the shared Container Apps environment. This plus `resource_group_name` is what a tenant needs to resolve it."
  value       = azurerm_container_app_environment.this.name
}

output "container_app_environment_id" {
  description = "ARM ID of the shared Container Apps environment, for a tenant that would rather pass the ID directly than resolve it by name."
  value       = azurerm_container_app_environment.this.id
}

output "location" {
  description = "Region the environment is in. A tenant's container apps and jobs may live in another resource group but must be in this region."
  value       = azurerm_resource_group.this.location
}

output "log_analytics_workspace_id" {
  description = "Workspace ID, for a tenant adding a diagnostic setting on a resource of its own."
  value       = azurerm_log_analytics_workspace.this.id
}

output "app_insights_connection_string" {
  description = "Application Insights connection string, which tenant workloads receive as `APPLICATIONINSIGHTS_CONNECTION_STRING`. Tenants normally read this from their own `azurerm_application_insights` data source rather than from here."
  value       = azurerm_application_insights.this.connection_string
  sensitive   = true
}

output "app_insights_name" {
  description = "Application Insights name, for a tenant's data source."
  value       = azurerm_application_insights.this.name
}

output "events_ingestion_endpoint" {
  description = "Logs Ingestion endpoint for `Deployments_CL`, `OpsEvents_CL` and `Costs_CL`. github-repos sets it on every app repo's dev environment as `EVENTS_INGESTION_ENDPOINT`, which the shared deploy workflow posts to."
  value       = azurerm_monitor_data_collection_endpoint.events.logs_ingestion_endpoint
}

output "events_dcr_immutable_id" {
  description = "Immutable ID of the events data collection rule, the part of the ingestion URL that names the rule. Set alongside the endpoint as `EVENTS_DCR_IMMUTABLE_ID`."
  value       = azurerm_monitor_data_collection_rule.events.immutable_id
}

output "events_dcr_id" {
  description = "ARM ID of the events data collection rule: the scope github-repos grants `Monitoring Metrics Publisher` on, for each identity allowed to send."
  value       = azurerm_monitor_data_collection_rule.events.id
}

output "postgres_server_name" {
  description = "Name of the shared Postgres server. It carries a random suffix (see main.database.tf), so tenants take it from here rather than deriving it."
  value       = azurerm_postgresql_flexible_server.this.name
}

output "postgres_fqdn" {
  description = "Host tenants connect to. Each tenant has its own database and login on it."
  value       = azurerm_postgresql_flexible_server.this.fqdn
}
