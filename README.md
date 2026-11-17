# azure-container-apps

A shared Azure Container Apps environment that any project can deploy onto.

This repository owns the environment and the observability behind it, and
little else: the event tables tenants report deploys and operations into.
**Nothing here bills while idle**: there is no container registry, no workload
profile and no database server (the shared Postgres server was removed in
2026-11, once nothing used it), and all ingestion stays inside the Log
Analytics free grant.

## What is shared, and what is not

| | Owned here | Owned by each project |
|---|---|---|
| Container Apps environment | yes | |
| Log Analytics workspace | yes | |
| Application Insights | yes | |
| Aspire dashboard (live traces, metrics, logs) | yes | |
| HTTP request logs (`ContainerAppHTTPLogs`) | yes | |
| Crash, HTTP-error, log-quota and ops-event alerts, and a budget | yes | |
| `Deployments_CL`, `OpsEvents_CL`, `Costs_CL` and their ingestion endpoint and rule | yes | sends rows |
| Resource group | for the above | its own |
| Key Vault | | its own |
| Managed identity | | its own |
| Container apps and jobs | | its own |
| Storage, anything else | | its own |

The Aspire dashboard is at `https://aspire-dashboard.ext.<default domain>`
(`make outputs` prints the default domain). It reads the OTLP data apps
already emit, so it costs nothing and ingests nothing into the workspace.

The split is deliberate. A project can be created, changed and destroyed without
touching this repository, and its secrets sit in a vault no other project's
identity can read.

**Sending events** needs `Monitoring Metrics Publisher` on the events rule,
granted to each repo's deploy identity in github-repos (a role assignment no
pipeline here may create). The shared deploy workflow writes a `Deployments_CL`
row on every deploy by itself; jobs write `OpsEvents_CL` heartbeats, and observability writes nightly `Costs_CL` rows.

**A container app or job may live in a different resource group from its
environment, but not a different region.** Everything deploying here must be in
`northeurope`.

## Onboarding a project

Resolve the environment by name rather than reading this repository's state —
no shared credentials, and the coupling stays a convention rather than a lock:

```hcl
data "azurerm_container_app_environment" "platform" {
  name                = var.platform_environment_name      # cae-platform-dev
  resource_group_name = var.platform_resource_group_name   # rg-platform-dev
}

data "azurerm_application_insights" "platform" {
  name                = var.platform_app_insights_name     # appi-platform-dev
  resource_group_name = var.platform_resource_group_name
}

resource "azurerm_container_app_job" "example" {
  name                         = "caj-example-dev-scan"
  container_app_environment_id = data.azurerm_container_app_environment.platform.id
  resource_group_name          = azurerm_resource_group.mine.name
  location                     = azurerm_resource_group.mine.location
  # ...
}
```

`make outputs` prints the current values.

### Two things to get right

**Do not set `command` on a container.** The image's `ENTRYPOINT` already names
its own executable, and setting it again in Terraform creates a second source of
truth that is not versioned with the code that defines it. market-agent took a
full outage in September 2026 from exactly this: a `command` under
`lifecycle { ignore_changes }` went stale against a renamed console script, and
every workload crash-looped on `executable file not found`. Use `args` to pick a
subcommand; let the image own the entrypoint.

**A job name must fit 32 characters**, and the naming module truncates silently
rather than failing. `caj-<project>-<env>-<workload>` is the shape; check with
`terraform console` before committing to a name.

### Plan `dev` only

A project's Terraform resolves this environment with a data source, so a plan
against an environment that has not been applied fails at plan time — reporting
a CI failure for something that is not a defect. Only `dev` is ever applied, so
a project's CI should plan `dev` alone rather than copying the dev/stg/prd
matrix used here.

## Alerting

Five log-query rules against the shared workspace, each split by workload or
check so one already firing does not mask another, and each covering tenants
added later with no change here.

**Workload crashed.** Any job or app emitting `ContainerCrashing`,
`BackoffLimitExceeded` or `StartError`: a container that never started, which
is the one failure a project's own code can never report, because none of it
ran. It is a log query rather than a metric alert on `Executions`
deliberately: the metric alert was tried in market-agent and verified on
2026-09-18 not to fire, despite a real failed execution.

**App errors.** 4xx/5xx responses from `ContainerAppHTTPLogs`, which the
environment ships only through the diagnostic setting here. 401s and
`/favicon.ico` 404s are excluded, and the rule counts repeats of the same
(app, path, status) in a window, so internet scanner sweeps don't fire it but
a path that keeps failing does. A tenant that serves public traffic with a
normal error rate should ask for a per-app exclusion rather than everyone
losing the signal.

**Log quota.** The 0.15 GB/day cap is shared. Reaching it stops ingestion for
every project for the rest of the day, including the rules above, which read
logs. Evaluated hourly, firing at 80% of the cap.

**Ops event bad.** The latest `OpsEvents_CL` row per check reports a problem:
Terraform drift (each repo's nightly `schedule-drift`), an expiring
certificate, an overdue job, a billable session resource left running, or a
failed cost feed (all from observability).

**Ops events silent.** Nothing has written to `OpsEvents_CL` for two days, so a
dead emitter can't pass for a quiet, healthy estate.

A schedule that silently never fires emits no log, so the rules can't see
it directly; observability's daily heartbeat check catches it and reports
`overdue` through `OpsEvents_CL`.

A **budget** on this resource group (`monthly_budget_amount`, default 5)
notifies at 80% actual and 100% forecast spend. Nothing here bills while
idle, so it is a backstop for a mistake, such as a workload profile attached
by hand. Each tenant's spend is its own group's budget.

Alerts reach whoever holds `Owner` on the subscription via an ARM role receiver,
plus the address in `var.alert_email_address`. The role receiver needs no
address in configuration or state, which is what makes it usable in a public
repository.

## Bootstrapping

Once, before the first apply:

```bash
az provider register --namespace Microsoft.App
az provider register --namespace Microsoft.OperationalInsights
az provider register --namespace Microsoft.Insights
```

The state container comes from github-repos (its `state_consumers` entry), not
from here. Don't create it with `az storage container create`: github-repos
would then fail to create it and need an `import`. On a fresh subscription,
apply just that container in github-repos first, because github-repos' full
apply looks up this repo's environment and events rule (factory's
`docs/greenfield.md` has the order).

`Microsoft.App` genuinely needs this — the environment fails with
`MissingSubscriptionRegistration` on a subscription where it has never been
registered.

Then apply dev by merging and running `cd-terraform` (see CI/CD below).
`make plan ENV=dev` previews it locally; `make apply` is only for stg or prd,
if they are ever brought up.

## Environments

`terraform/environments/{dev,stg,prd}.tfvars` are the per-environment inputs.
**Only `dev` is planned in CI and applied**, because only `dev` has an Azure
identity; CI validates all three. The plumbing is kept so that changing this is
a decision rather than a rebuild.

These files are committed intentionally. Do not put secrets in them — gitleaks
scans as a backstop.

## State

State lives in an Azure storage account shared with the other Terraform root
configurations, in a container of this repository's own name. The
`backend "azurerm" {}` block is **partial**: per-environment values are in
`terraform/backends/<env>.hcl`.

The consequence is that a plain `terraform init` prompts, and fails outright
under `-input=false`. Anything not touching state must use `init -backend=false`
— `make init` and `make validate` both do. `terraform console`, unlike
`validate`, needs a real backend.

## Commands

Once per machine, set up the tools with
[jay-withers/toolchain](https://github.com/jay-withers/toolchain), which
installs [mise](https://mise.jdx.dev). `mise.toml` pins Terraform, TFLint,
terraform-docs, Checkov and pre-commit, and CI installs the same versions.

```bash
make install    # mise tools and pre-commit hooks
make lint       # every hook against every file
make fmt        # terraform fmt -recursive
make validate   # init + validate, no Azure credentials
make plan       # init + plan     (ENV=dev|stg|prd, default dev)
make apply      # init + apply    (stg/prd only, if ever; dev is applied by running cd-terraform)
make outputs    # the values a project needs to point at this environment
```

Generated input/output reference: [`terraform/README.md`](terraform/README.md).

## CI/CD

Every workflow is a thin caller of a shared one in
[jay-withers/workflows](https://github.com/jay-withers/workflows), pinned by
SHA. Required checks: `pre-commit / Pre-commit`, `terraform / Terraform` and
`terraform-plan`.

- **ci-pre-commit**: every hook (fmt, validate, docs, TFLint and Checkov per
  environment, the file-layout check, gitleaks, actionlint).
- **ci-terraform**: credential-free validate of all three environments, then
  a real plan of dev, commented on the PR.
- **ci-codeql**: CodeQL code scanning of the workflows.
- **cd-terraform**: plans dev on merge and opens a `terraform-pending` issue
  when there are changes; **Actions → cd-terraform → Run workflow** applies.
- **cd-tag**: a semver tag and release on every merge to `main`.
- **schedule-drift**: a nightly plan of dev, recorded in `OpsEvents_CL`, so
  drift raises the ops-event alert.
- **manual-terraform-unlock**: releases a stuck state lock, given the lock ID
  from an "Error acquiring the state lock" message.

The state container, the OIDC identity and the `dev` environment's variables
come from [github-repos](https://github.com/jay-withers/github-repos), as do
this repo's settings and required checks.
