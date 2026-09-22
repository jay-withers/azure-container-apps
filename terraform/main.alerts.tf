# Alerting for the shared environment, and mostly for things the platform
# itself can see. A tenant's own failures — an empty result, a wrong answer, a
# spend cap — are the tenant's to detect and report; what a tenant cannot
# report is a container that never started, because nothing of its code ever
# ran. That is what the job-failure rule below is for.
#
# HTTP status codes are the one tenant-shaped signal alerted on here anyway,
# and that is specific to what this environment hosts: every tenant today is
# an agent calling agent-shaped traffic (its own jobs, other services), not a
# public app fielding arbitrary end users, so a 4xx here is not "someone typed
# the wrong thing" noise — it is one agent-shaped workload failing to talk to
# another, which is exactly the cross-cutting failure a shared rule is for. If
# a future tenant serves public traffic, its own normal 4xx rate will trip
# this rule, and that tenant should ask for a per-app exclusion rather than
# everyone losing the signal.

# ---------------------------------------------------------------------------
# Where alerts go
# ---------------------------------------------------------------------------

# An ARM role receiver rather than an address, because this repository is
# public and `terraform/environments/*.tfvars` are committed. Azure resolves the
# role to whoever currently holds it on the subscription, so there is nothing to
# commit, nothing in state, and nothing to update when the person changes.
resource "azurerm_monitor_action_group" "this" {
  name                = module.naming.monitor_action_group.name
  resource_group_name = azurerm_resource_group.this.name

  # Max 12 characters, and it is what appears in the email subject.
  short_name = substr(var.project_name, 0, 12)

  arm_role_receiver {
    name    = "subscription-owners"
    role_id = local.owner_role_definition_id

    # The common schema is the one that stays stable across alert types, so a
    # webhook added later does not have to parse several payload shapes.
    use_common_alert_schema = true
  }

  # A second receiver alongside the role, not instead of it. Empty disables it;
  # `dynamic` rather than a static block so an empty string means no receiver
  # rather than a receiver with no address.
  dynamic "email_receiver" {
    for_each = var.alert_email_address == "" ? [] : [var.alert_email_address]
    content {
      name                    = "configured-address"
      email_address           = email_receiver.value
      use_common_alert_schema = true
    }
  }

  tags = local.tags
}

# ---------------------------------------------------------------------------
# A tenant job that failed to start
# ---------------------------------------------------------------------------

# One rule covering every tenant, including tenants that do not exist yet. It
# needs no edit when a project is added, which is the whole reason it lives here
# rather than in each tenant's own configuration.
#
# **Why a log query and not the `Executions` metric.** The obvious rule is a
# metric alert on `Microsoft.App/jobs` `Executions` filtered to
# `state == Failed`. That was tried in market-agent and verified on 2026-09-18
# not to fire: a genuinely failed execution held the metric at 1 for several
# minutes, comfortably inside a 15-minute window, and
# `Microsoft.AlertsManagement/alerts` still showed nothing days later. The rule
# was correct by every check Terraform can express, so this reads as a
# platform-side gap in alerting on that metric. `ContainerAppSystemLogs_CL`
# carries the same failure and ingests reliably.
#
# **Why `dimension` and not `resource_id_column`.** Splitting by the job's ARM
# ID would be tidier, but that ID cannot be built from this table: it has no
# resource group column, and `_ResourceId` is empty on every row (checked across
# 1,701 rows). Deriving the resource group from the job name by string surgery
# would hardcode a cross-repo naming convention into a KQL string, and point at
# a non-existent resource the moment a tenant named its group differently.
# Splitting on `JobName_s` needs no such assumption and still tracks each job as
# its own alert, so one job already firing does not mask a second.
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "job_failed" {
  name                = "alert-${local.alert_name_prefix}-job-failed"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  description         = "A container app job on the shared environment crashed instead of running to completion."
  severity            = 1

  scopes                = [azurerm_log_analytics_workspace.this.id]
  evaluation_frequency  = "PT5M"
  window_duration       = "PT15M"
  target_resource_types = ["Microsoft.OperationalInsights/workspaces"]

  criteria {
    # The three reasons a real crash loop is observed to emit: the exec/OCI
    # failure itself, the job giving up, and the replica's own failure record.
    # `Log_s` is projected so the alert payload carries the actual error rather
    # than only a count.
    query = <<-KQL
      ContainerAppSystemLogs_CL
      | where Reason_s in ("ContainerCrashing", "BackoffLimitExceeded", "StartError")
      | where isnotempty(JobName_s)
      | project TimeGenerated, JobName_s, Reason_s, Log_s
    KQL

    time_aggregation_method = "Count"
    operator                = "GreaterThan"
    threshold               = 0

    # Include everything: a tenant added later is covered without an edit here.
    dimension {
      name     = "JobName_s"
      operator = "Include"
      values   = ["*"]
    }

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.this.id]
  }

  tags = local.tags
}

# Known gap, stated rather than left to be discovered: a schedule that silently
# never fires emits no log at all, so nothing above catches it. The tenant's own
# output going missing is the only signal, which is a reason for a tenant to
# send something on every run even when it has nothing to report.

# ---------------------------------------------------------------------------
# A tenant app returning a client or server error
# ---------------------------------------------------------------------------

# Reads `ContainerAppHTTPLogs`, populated by the diagnostic setting in
# main.observability.tf — the environment doesn't ship this data any other
# way. Same shape as the job-failure rule above and for the same reason: one
# rule, split on the `ContainerAppName` dimension, covers every app including
# ones that don't exist yet.
#
# `GreaterThan 0`, matching the job-failure rule, is a deliberately low bar —
# there's no real-traffic data yet on what a normal error rate looks like for
# these workloads (see the file header for why any error is treated as
# signal here rather than noise). If a tenant's ordinary operation turns out
# to produce occasional 4xx/5xx, raise this threshold or add a per-app
# exclusion rather than dropping the rule, so a genuinely broken tenant is
# still caught.
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "app_error" {
  name                = "alert-${local.alert_name_prefix}-app-error"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  description         = "A container app on the shared environment returned a 4xx or 5xx response."
  severity            = 2

  scopes                = [azurerm_log_analytics_workspace.this.id]
  evaluation_frequency  = "PT5M"
  window_duration       = "PT15M"
  target_resource_types = ["Microsoft.OperationalInsights/workspaces"]

  criteria {
    query = <<-KQL
      ContainerAppHTTPLogs
      | where StatusCode >= 400
      | project TimeGenerated, ContainerAppName, Method, Path, StatusCode, ResponseCodeDetails
    KQL

    time_aggregation_method = "Count"
    operator                = "GreaterThan"
    threshold               = 0

    # Include everything: a tenant app added later is covered without an edit
    # here.
    dimension {
      name     = "ContainerAppName"
      operator = "Include"
      values   = ["*"]
    }

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.this.id]
  }

  tags = local.tags
}

# ---------------------------------------------------------------------------
# The monitoring watching itself
# ---------------------------------------------------------------------------

# Reaching `daily_quota_gb` stops ingestion for the rest of the day — for every
# tenant at once, now that the workspace is shared — which silently disables the
# job-failure rule above along with every log it reads. Nothing in the metric
# store reports it, so this has to be a log query.
#
# Hourly: measured ingestion is a fraction of a percent of the cap, so the event
# this catches is a runaway rather than growth, and an hour's notice of a runaway
# is plenty. Log alerts are the expensive kind, which is the other reason.
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "log_quota" {
  name                = "alert-${local.alert_name_prefix}-log-quota"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  description         = "Shared log ingestion is approaching the workspace daily cap, past which logging stops for every tenant."
  severity            = 2

  scopes                = [azurerm_log_analytics_workspace.this.id]
  evaluation_frequency  = "PT1H"
  window_duration       = "P1D"
  target_resource_types = ["Microsoft.OperationalInsights/workspaces"]

  criteria {
    # `Usage` is billed volume in megabytes and is the same figure the cap is
    # applied to. `IsBillable` matters: the free data types do not count towards
    # the quota, so including them would warn on volume that cannot reach it.
    query = <<-KQL
      Usage
      | where TimeGenerated > ago(1d) and IsBillable == true
      | summarize IngestedGb = sum(Quantity) / 1024
    KQL

    time_aggregation_method = "Total"
    metric_measure_column   = "IngestedGb"
    operator                = "GreaterThan"
    threshold               = local.log_quota_alert_gb

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.this.id]
  }

  tags = local.tags
}

# ---------------------------------------------------------------------------
# Cost
# ---------------------------------------------------------------------------

# This configuration has no standing cost: no database, no workload profile, no
# registry, and everything inside the Log Analytics free grant. So this budget
# is not watching for growth in normal operation — there is none to watch. It is
# the backstop for a mistake: a workload profile attached to the environment by
# hand, a tenant logging at speed, or a resource created in the portal and
# forgotten. Each of those bills quietly and none of them is visible from a
# tenant's own telemetry.
#
# 100% is `Forecasted` rather than `Actual`: hearing that the month will overrun
# while there is still a month left to act is the useful warning.
resource "azurerm_consumption_budget_resource_group" "this" {
  name              = "budget-${local.alert_name_prefix}"
  resource_group_id = azurerm_resource_group.this.id

  amount     = var.monthly_budget_amount
  time_grain = "Monthly"

  time_period {
    start_date = var.budget_start_date
  }

  notification {
    enabled        = true
    threshold      = 80
    threshold_type = "Actual"
    operator       = "GreaterThan"
    contact_roles  = ["Owner"]
  }

  notification {
    enabled        = true
    threshold      = 100
    threshold_type = "Forecasted"
    operator       = "GreaterThan"
    contact_roles  = ["Owner"]
  }

  lifecycle {
    # Azure refuses a start date in a past month on create but reports the
    # stored one thereafter, so leaving this tracked makes the first apply of a
    # new month a spurious replacement.
    ignore_changes = [time_period[0].start_date]
  }
}

# Note this budget covers **this** resource group only. Each tenant's spend
# lands in the tenant's own group and is the tenant's own budget to set.
