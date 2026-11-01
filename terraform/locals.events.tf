locals {
  # The custom tables tenants write to through the Logs Ingestion
  # API, and that Grafana reads. Each list is the table's schema *and* the DCR's
  # stream declaration, so the two cannot drift: a column the stream sends but
  # the table lacks is dropped silently, with nothing in any log to say so.
  #
  # `TimeGenerated` is mandatory on every custom table. The sender sets it, so
  # a row records when the thing happened, not when it was ingested.
  event_tables = {
    # One row per run of jay-withers/workflows' container-apps-deploy.yml,
    # written by its last step whatever the outcome.
    Deployments_CL = [
      { name = "TimeGenerated", type = "datetime" },
      { name = "Repo", type = "string" },
      { name = "App", type = "string" },
      { name = "Environment", type = "string" },
      { name = "Version", type = "string" },
      { name = "PreviousVersion", type = "string" },
      # success | rolled_back | failed | untested
      { name = "Outcome", type = "string" },
      # renovate | manual, from the merge commit's author
      { name = "Trigger", type = "string" },
      { name = "CommitSha", type = "string" },
      { name = "RunUrl", type = "string" },
      { name = "LeadTimeSec", type = "int" },
    ]

    # Everything operational that isn't a deploy: job heartbeats, drift plans,
    # expiry checks, restore tests. One table with a `Kind` rather than one per
    # source, so a "no events in N days" check covers every emitter at once.
    OpsEvents_CL = [
      { name = "TimeGenerated", type = "datetime" },
      { name = "Repo", type = "string" },
      { name = "Environment", type = "string" },
      # heartbeat | drift | expiry | restore | session | cost-feed
      { name = "Kind", type = "string" },
      # what it is about: a job name, a Terraform root, a secret, a database
      { name = "Name", type = "string" },
      # ok | failed | drifted | expiring | overdue | running
      { name = "Status", type = "string" },
      { name = "Detail", type = "string" },
      { name = "RunUrl", type = "string" },
    ]

    # Daily cost per resource group and service, from Cost Management's query
    # API, written nightly by observability's schedule-costs. Each run re-sends
    # the last seven days, because Azure revises a day's figure for about three
    # afterwards, so readers take the latest row per UsageDate, ResourceGroup and
    # ServiceName. Cost is ActualCost before any credit: on a Visual Studio
    # subscription, what the estate would cost on pay-as-you-go.
    Costs_CL = [
      { name = "TimeGenerated", type = "datetime" },
      { name = "UsageDate", type = "datetime" },
      { name = "ResourceGroup", type = "string" },
      { name = "ServiceName", type = "string" },
      { name = "Cost", type = "real" },
      { name = "Currency", type = "string" },
      { name = "RunUrl", type = "string" },
    ]
  }
}
