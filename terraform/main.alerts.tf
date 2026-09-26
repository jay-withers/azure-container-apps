# Alerting for the shared environment, and mostly for things the platform
# itself can see. A tenant's own failures — an empty result, a wrong answer, a
# spend cap — are the tenant's to detect and report; what a tenant cannot
# report is a container that never started, because nothing of its code ever
# ran. That is what the workload-crashed rule below is for.
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
# A tenant job or app that crashed instead of running
# ---------------------------------------------------------------------------

# One rule covering every tenant, including tenants that do not exist yet. It
# needs no edit when a project is added, which is the whole reason it lives here
# rather than in each tenant's own configuration.
#
# Originally job-only: it filtered on `isnotempty(JobName_s)`, so a
# long-running app hitting the same reasons — `ContainerCrashing` from a
# revision that never comes up healthy, say — raised nothing. Verified on
# 2026-09-22 that `ContainerAppSystemLogs_CL` populates `ContainerAppName_s`
# for real apps in this workspace (`ca-gymlog-dev`, `ca-finances-dev`, …) the
# same way it populates `JobName_s` for jobs, just never both on the same row,
# so `coalesce()` is enough to unify them into one workload name with no risk
# of silently dropping one arm.
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
# **Why `dimension` and not `resource_id_column`.** Splitting by ARM ID would
# be tidier, but that ID cannot be built from this table: it has no resource
# group column, and `_ResourceId` is empty on every row (checked across 1,701
# rows). Deriving the resource group from the workload name by string surgery
# would hardcode a cross-repo naming convention into a KQL string, and point at
# a non-existent resource the moment a tenant named its group differently.
# Splitting on the coalesced name needs no such assumption and still tracks
# each workload as its own alert, so one already firing does not mask another.
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "workload_crashed" {
  name                = "alert-${local.alert_name_prefix}-workload-crashed"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  description         = "A container app or job on the shared environment crashed instead of running normally."
  severity            = 1

  # Left unset, every rule in this file deployed with `autoMitigate: false` at
  # the ARM layer (verified against the live rules on 2026-09-22), which
  # re-notifies on every evaluation period the condition still holds rather
  # than once on the OK-to-Alert transition. A single ongoing incident — a job
  # crash-looping every run, an app erroring on every request — then re-fires
  # every `evaluation_frequency` for as long as it lasts, which is what turned
  # two real incidents (market-agent's sync jobs and its api's auth failures)
  # into dozens of emails. Explicit `true` on every rule below for the same
  # reason.
  auto_mitigation_enabled = true

  scopes                = [azurerm_log_analytics_workspace.this.id]
  evaluation_frequency  = "PT5M"
  window_duration       = "PT15M"
  target_resource_types = ["Microsoft.OperationalInsights/workspaces"]

  criteria {
    # The three reasons a real crash loop is observed to emit: the exec/OCI
    # failure itself, the workload giving up, and the replica's own failure
    # record. `Log_s` is projected so the alert payload carries the actual
    # error rather than only a count.
    #
    # `union isfuzzy=true` rather than referencing the table directly:
    # `ContainerAppSystemLogs_CL` is created lazily on first ingestion, so it
    # does not exist until some tenant workload has crashed at least once. A
    # plain reference fails rule creation itself with "Failed to resolve
    # table" the moment the workspace is new. Fuzzy union alone isn't enough
    # either — with a single operand Azure still rejects the query once that
    # one table fails to resolve — so the empty `datatable` gives it a second
    # operand that always resolves, contributing zero rows either way.
    query = <<-KQL
      union isfuzzy=true
        ContainerAppSystemLogs_CL,
        (datatable(TimeGenerated: datetime, JobName_s: string, ContainerAppName_s: string, Reason_s: string, Log_s: string) [])
      | where Reason_s in ("ContainerCrashing", "BackoffLimitExceeded", "StartError")
      | where isnotempty(JobName_s) or isnotempty(ContainerAppName_s)
      | extend WorkloadName = coalesce(JobName_s, ContainerAppName_s)
      | project TimeGenerated, WorkloadName, Reason_s, Log_s
    KQL

    time_aggregation_method = "Count"
    operator                = "GreaterThan"
    threshold               = 0

    # Include everything: a tenant added later is covered without an edit here.
    dimension {
      name     = "WorkloadName"
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
# way. Same shape as the workload-crashed rule above and for the same reason:
# one rule, split on the `ContainerAppName` dimension, covers every app
# including ones that don't exist yet.
#
# `GreaterThan 0`, matching the workload-crashed rule, is a deliberately low bar —
# there's no real-traffic data yet on what a normal error rate looks like for
# these workloads (see the file header for why any error is treated as
# signal here rather than noise). If a tenant's ordinary operation turns out
# to produce occasional 4xx/5xx, raise this threshold or add a per-app
# exclusion rather than dropping the rule, so a genuinely broken tenant is
# still caught.
#
# `StatusCode != 401` excludes one specific case rather than being covered by
# that per-app exclusion: unauthenticated scanner/bot traffic against a public
# app. Verified on 2026-09-23 against market-agent's dashboard and api, which
# this environment's first public-facing tenant made unavoidable — 66 of 75
# 4xx/5xx logged over 7 days were 401s from scattered source IPs and user
# agents sweeping `/`, `/robots.txt`, `/sitemap.xml`, `/config.json` and every
# `/api/*` route, which the app correctly rejected. That is background noise
# any public app on the internet gets continuously, not a signal a per-app
# exclusion would be right to silence for one tenant — the next public tenant
# hits the same thing. A 401 caused by a tenant's own auth actually breaking
# (an expired identity, a misconfigured secret) is a real gap this leaves, but
# it fires from inside the platform against a known caller, which is exactly
# the shape a tenant's own monitoring is positioned to catch and this shared
# rule is not.
#
# `/favicon.ico` returning 404 is excluded for the same reason as the 401s
# above, not because it is the same failure mode. Verified on 2026-09-23 on
# gymlog: every 4xx/5xx it has ever logged, three for three, is a browser
# auto-requesting a favicon the app never chose to serve. That is standard
# browser behavior on any app without one, not evidence the workload is
# broken, and the next browser-facing tenant without a favicon route hits the
# same thing.
#
# The query is grouped into a repeat count per (app, path, status) rather
# than a raw row count for the same underlying reason as the 401/favicon
# exclusions, but that a path exclusion cannot reach: unauthenticated
# vulnerability-scanner traffic, which does not park on one or two known
# paths the way the 401 sweep did. Verified on 2026-09-26 on gymlog: 1,963
# 4xx/5xx logged over 7 days (already past the 401/favicon filters) came from
# 155 distinct source IPs across ~1,875 distinct paths — `/wp-includes/...`,
# `/.env*`, `/.git/config`, `/old.sql.*`, `/actuator/env`, Jira/Confluence and
# Spring Boot exploit probes, and more, rotating constantly — with the same
# (path, status) pair repeating at most twice in any single 15-minute window.
# A path- or extension-based exclusion would be a losing, ever-growing list
# chasing scanners that never stop rotating signatures. Grouping first and
# thresholding on the repeat count instead needs no such list, and is a
# structural difference from real trouble: the one genuine failure gymlog
# logged in the same 7 days — `/garmin/sync` returning 500 three times in 15
# minutes during a transient Garmin-side outage — sat exactly at the
# threshold below, which a scanner sweep never reached even once. Losing a
# truly one-off failure that never recurs within a window is the accepted
# trade-off, same as the 401/favicon exclusions accept losing a one-off auth
# fluke — a tenant's own monitoring is what is positioned to catch that,
# this shared rule is not.
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "app_error" {
  name                = "alert-${local.alert_name_prefix}-app-error"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  description         = "A container app on the shared environment returned a 4xx or 5xx response."
  severity            = 2

  # See the workload-crashed rule above for why this is explicit rather than
  # left to default to false.
  auto_mitigation_enabled = true

  scopes                = [azurerm_log_analytics_workspace.this.id]
  evaluation_frequency  = "PT5M"
  window_duration       = "PT15M"
  target_resource_types = ["Microsoft.OperationalInsights/workspaces"]

  criteria {
    # Known open question, not yet resolved: apps here scale to zero
    # (min_replicas = 0 is the point of a consumption-only environment), and
    # Envoy can return a 5xx from ingress itself while a replica cold-starts,
    # before any tenant code runs. Azure's documented signal for that is
    # `ResponseFlags == "UH"` (no healthy upstream) or `ResponseCodeDetails ==
    # "no_healthy_upstream"`, as opposed to `via_upstream` for an error the
    # app returned itself — but `ContainerAppHTTPLogs` has zero rows on this
    # environment so far, so there's nothing here to check that against yet.
    # `ResponseFlags` is projected so the first real firing settles it: if
    # cold starts turn out to trip this rule, exclude on that flag rather than
    # on `StatusCode == 503` broadly, since an app can legitimately return its
    # own 503.
    #
    # `arg_max(TimeGenerated, ...)` rather than separate `any()`s per column:
    # it keeps Method/ResponseCodeDetails/ResponseFlags from the one row that
    # produced the max TimeGenerated, so the alert payload describes one real
    # request instead of an inconsistent mix from whichever rows `any()`
    # happened to pick independently per column.
    query = <<-KQL
      ContainerAppHTTPLogs
      | where StatusCode >= 400 and StatusCode != 401
      | where not (Path == "/favicon.ico" and StatusCode == 404)
      | summarize FailureCount = count(), arg_max(TimeGenerated, Method, ResponseCodeDetails, ResponseFlags)
        by ContainerAppName, Path, StatusCode
      | where FailureCount >= 3
      | project TimeGenerated, ContainerAppName, Method, Path, StatusCode, ResponseCodeDetails, ResponseFlags, FailureCount
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
# workload-crashed rule above along with every log it reads. Nothing in the metric
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

  # See the workload-crashed rule above for why this is explicit rather than
  # left to default to false: without it, a day spent over the 80% threshold
  # re-notifies every hourly evaluation instead of once.
  auto_mitigation_enabled = true

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
