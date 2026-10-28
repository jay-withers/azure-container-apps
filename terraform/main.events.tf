# Deploy and operational events, sent by tenants (and by the shared deploy
# workflow on their behalf) through the Logs Ingestion API: a POST to the data
# collection endpoint, naming this rule and a stream. Nothing here bills while
# idle — the endpoint and rule are free, and the rows count against the same
# workspace cap as everything else, at a few hundred bytes each.
#
# Who may send is decided by `Monitoring Metrics Publisher` on the rule. That is
# a role assignment, which no pipeline identity is allowed to create, so it is
# granted in jay-withers/github-repos alongside each repo's deploy identity, not
# here.

# The custom tables, through azapi: azurerm can only manage the retention of a
# table that already exists, not create one with a schema.
resource "azapi_resource" "event_table" {
  for_each = local.event_tables

  type      = "Microsoft.OperationalInsights/workspaces/tables@2022-10-01"
  name      = each.key
  parent_id = azurerm_log_analytics_workspace.this.id

  body = {
    properties = {
      schema = {
        name    = each.key
        columns = each.value
      }
      # Same 30 days as the workspace, which is free. Deploy history older than
      # that lives in each repo's releases and Actions runs.
      retentionInDays = 30
    }
  }
}

resource "azurerm_monitor_data_collection_endpoint" "events" {
  name                = "dce-${var.project_name}-${var.environment}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location

  # Senders are GitHub-hosted runners and Container Apps jobs, neither of
  # which has a private network to come from. The rule's role assignment, not
  # the network, is what keeps writes to known identities.
  public_network_access_enabled = true

  tags = local.tags
}

resource "azurerm_monitor_data_collection_rule" "events" {
  name                        = "dcr-${var.project_name}-events-${var.environment}"
  resource_group_name         = azurerm_resource_group.this.name
  location                    = azurerm_resource_group.this.location
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.events.id

  destinations {
    log_analytics {
      name                  = "workspace"
      workspace_resource_id = azurerm_log_analytics_workspace.this.id
    }
  }

  dynamic "stream_declaration" {
    for_each = local.event_tables

    content {
      stream_name = "Custom-${stream_declaration.key}"

      dynamic "column" {
        for_each = stream_declaration.value

        content {
          name = column.value.name
          type = column.value.type
        }
      }
    }
  }

  # `source` passes rows through unchanged: shaping happens in the sender,
  # where it can be tested, rather than in KQL nobody runs locally.
  dynamic "data_flow" {
    for_each = local.event_tables

    content {
      streams       = ["Custom-${data_flow.key}"]
      destinations  = ["workspace"]
      output_stream = "Custom-${data_flow.key}"
      transform_kql = "source"
    }
  }

  tags = local.tags

  # A data flow into a table that does not exist yet is rejected by ARM.
  depends_on = [azapi_resource.event_table]
}
