# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo does

Terraform for the **one** Azure Container Apps environment every project
deploys onto, plus the Log Analytics workspace, Application Insights and
alerting behind it, the event tables tenants report into, and one shared
Postgres server. It deliberately holds nothing else.

The split it enforces:

| | Owned here | Owned by each project |
| --- | --- | --- |
| Container Apps environment | yes | no |
| Log Analytics, App Insights | yes | no |
| Job-failure, log-quota and ops-event alerts, budget | yes | no |
| `Deployments_CL`/`OpsEvents_CL`, their DCE and DCR | yes | sends rows |
| Postgres **server** | yes, one shared | its own database and login |
| Resource group | its own | its own |
| Key Vault, managed identity | **no** | yes |
| Container apps and jobs | **no** | yes |

A tenant can be created, changed and destroyed without touching this
configuration, and its secrets live in a vault no other tenant's identity can
read. Do not add a Key Vault, an identity or a workload here — the moment this
repo owns a tenant's resources, tenants stop being independent and this becomes
the bottleneck it exists to avoid.

`jay-withers/repo-agent` is the first tenant and the worked example.

## How a tenant consumes it

By **name and resource group**, through a data source — never
`terraform_remote_state`:

```hcl
data "azurerm_container_app_environment" "platform" {
  name                = var.platform_environment_name # cae-platform-dev
  resource_group_name = var.platform_resource_group_name
}
```

No tenant needs access to this repository's state, and the coupling stays a
convention rather than a lock. `make outputs` prints exactly the values a
tenant needs.

Two consequences that bite:

- **A container app or job may live in a different resource group from its
  environment, but not a different region.** `var.location` is therefore
  binding on every tenant, not just on this configuration.
- **A data source against a not-yet-applied dependency fails at *plan* time**,
  which is why a tenant repo should plan only environments that actually exist.
  Since only `dev` is ever applied, tenants plan dev alone rather than copying
  a dev/stg/prd matrix.

## The cost constraint

Nothing here bills while idle, and that is the whole design, **with one
deliberate exception: the shared Postgres server** (`main.database.tf`). B1ms
has no serverless or auto-pause tier, so it bills ~£13/month for as long as it
exists. It is here because one shared server is the cheapest way to give
every tenant (market-agent, Grafana) a database at all; a server per project
per environment was the alternative. `monthly_budget_amount` was raised from 5
to 25 for it. Do not add a second standing cost without the same trade-off
being made out loud:

- **The environment has no `workload_profile` block.** A workload profile is a
  standing per-hour charge whether or not anything runs. Consumption-only is
  what lets tenant apps scale to zero and tenant jobs bill only for the seconds
  they execute. This is the single most important line in the repository; do
  not add one without raising the trade-off.
- **There is no Azure Container Registry**, for the same reason it was rejected
  in market-agent: ACR Basic is a flat monthly charge with no consumption tier.
  Images live in ghcr.io.
- `daily_quota_gb = 0.15` on the workspace and `daily_data_cap_in_gb = 0.1` on
  Application Insights. Azure Monitor's free grant is 5 GB/month and the
  default App Insights cap is 100 GB/day, so log ingestion is the largest cost
  risk here by a wide margin.

**The ingestion cap is now shared across every tenant**, which market-agent's
was not. Reaching it stops ingestion for all of them for the rest of the day —
and that is the one failure that blinds everything else, because the
job-failure alert reads logs rather than metrics. Measured ingestion on
market-agent is ~0.0005 GB/day, so 0.15 is watching for a runaway (a
crash-looping replica logging at speed) rather than for growth.
`local.log_daily_quota_gb` feeds both the workspace and the alert threshold so
the two cannot drift.

## Alerting

**The job-failure alert is a log query, not a metric alert, and that was
learned the hard way.** market-agent's equivalent watched the `Executions`
metric with `state = Failed`. That metric is a **gauge sampled per minute, not
a counter** — it reports how many executions are in each state *right now* — and
the rule never fired despite the metric crossing its threshold, verified across
seven days of a real outage in which every workload was crash-looping. It was
replaced there and is not reproduced here.

**`ops_event_bad` and `ops_events_silent` read `OpsEvents_CL`, not
platform logs.** The first fires on the latest `failed`, `drifted`,
`expiring` or `overdue` row per Kind and Name (drift from terraform-deploy's
nightly check, expiry and job heartbeats from observability); the second when
the table gets nothing for six hours, so a dead emitter can't pass for a quiet
estate. Job liveness is computed in observability, not here: learning a
weekly job's cadence needs 30 days of history, and a log alert's window is at
most two.

This rule reads `ContainerAppSystemLogs_CL` for
`ContainerCrashing`/`BackoffLimitExceeded`/`StartError`, which is a property of
the shared workspace, so **one rule covers every tenant with no edit here when
a new one deploys**.

It splits on the `JobName_s` **dimension** rather than using
`resource_id_column`, and that is not a style choice: `ContainerAppSystemLogs_CL`
carries no resource group column and `_ResourceId` is **empty on every row**
(verified across 1,701 rows), so there is nothing to build an ARM ID from. An
earlier draft of the plan assumed there was.

Known gap, worth stating rather than discovering: **a cron that silently never
fires emits no log and raises nothing.** A missing digest email is the only
signal. Fixing that needs a tenant-side heartbeat, not a rule here.

Other decisions not to re-litigate:

- **No availability tests.** A synthetic ping keeps a `min_replicas = 0` app
  permanently warm, which costs more than the outage it would detect.
- **No diagnostic setting on the environment.** It already ships console and
  system logs to the workspace via `log_analytics_workspace_id`; a diagnostic
  setting ingests every line a second time against the shared cap.
- **No `AllMetrics` anywhere.** Metrics are already in the platform metric
  store, free to query and free to alert on.
- **The log-quota alert is evaluated hourly** because reaching the cap stops
  ingestion for the rest of the day and nothing in the metric store reports it.
  It fires at 80% of the cap — warning while there is still headroom is the only
  useful moment.
- **The budget notifies, it does not stop anything.** Azure budgets never do.

Alerts reach subscription Owners through an `arm_role_receiver`, which needs no
address in config or state. `alert_email_address` adds a specific address on
top; note it has a **committed default**, which is a deliberate departure from
market-agent, where the recipient was kept in Key Vault precisely because that
repository is public. An address is an identifier rather than a credential, but
it is permanent in this repository's history — override with
`TF_VAR_alert_email_address` to keep a different one out of git.

## Naming

`.name`, not `.name_unique`. Tenants resolve the environment **by name**, so a
random suffix would make that convention unusable — this is a harder
requirement here than it was in market-agent, where it was a preference.

At `project_name = "platform"`, `environment = "dev"`:

```
rg-platform-dev      cae-platform-dev (16/32)
log-platform-dev     appi-platform-dev
mag-platform-dev
```

`project_name` is validated to 2–15 lowercase alphanumerics. The binding
constraint is the 32 characters a Container Apps environment allows. Container
app environments, apps and jobs all reject uppercase.

**Changing `project_name` after any tenant exists means updating every tenant**,
since each names the environment in its own tfvars. Treat it as fixed once
anything has deployed.

**The Postgres server is the exception: `.name_unique`.** Its name is a
public DNS label, unique across all of Azure, and tenants never resolve it by
data source; they read its FQDN from `make outputs`. The DCE and DCR are named
by hand (`dce-platform-dev`, `dcr-platform-events-dev`).

Two rules hold that the naming module does not: there is no
`monitor_scheduled_query_rules_alert` token for two distinct rules, so both are
named by hand from `local.alert_name_prefix`; and apart from the Postgres
server, Key Vault-style global uniqueness does not apply to anything here.

## Events and the shared database

- **`local.event_tables` is both the tables' schema and the DCR's stream
  declaration.** A column the sender includes but the table lacks is dropped
  without any error anywhere, so the two come from one list.
- **The tables are `azapi_resource`**: azurerm can only manage the retention of
  a custom table that already exists, not create one with columns.
- **Who may send is a role assignment** (`Monitoring Metrics Publisher` on the
  DCR), granted in github-repos next to each deploy identity, never here: a
  pipeline identity cannot create role assignments.
- **Password auth is on for Grafana alone.** Its database connection cannot
  use an Entra token. Every other role is Entra. `pgadmin`'s password exists
  only in state and is never output or used.
- **`prevent_destroy` on the server and on `grafana`.** Every tenant's data is
  on this server.

## Terraform layout

`terraform/` is a **deployable root configuration**, not a reusable module: it
has its own `provider` block in `versions.tf` and `.terraform.lock.hcl` is
committed. The Terraform version is pinned in `.terraform-version`.

**File layout is enforced, not conventional**: `locals`/`variable`/`output`/
`data` blocks must live in a matching `locals.tf`/`variables.tf`/`outputs.tf`/
`data.tf`, or a topic-scoped variant (`main.container-apps-env.tf`,
`locals.observability.tf`), via the local pre-commit hook
`scripts/check-tf-standards.sh`. That script is **shared verbatim** with
`market-agent`, `terraform-root-aks`, `azure-landingzone` and `github-repos` —
a change here should be re-copied there rather than allowed to diverge.

Variables are split by whether they must be supplied: `variables.required.tf`
(only `environment`) and `variables.optional.tf` (everything with a default).

**Comments and outputs earn their place.** Comment the non-obvious — a cost
trade-off, a provider quirk, a trap — not what the code already says. Add an
output because something consumes it; here that means a tenant.

**The lock file must carry hashes for every platform that runs Terraform.**
`terraform providers lock -platform=linux_amd64 -platform=linux_arm64
-platform=darwin_arm64`. A lock file with arm64 hashes only fails
`pre-commit / Pre-commit` in CI on every PR, because CI runs amd64, adds a hash
during `init`, and the modified tracked file trips the hook. This has already
happened once.

## State and the partial backend

State lives in `sttfsharedjw` / `rg-tfstate-shared`, container
`azure-container-apps`, created by `github-repos`' Terraform
(`state_consumers`) along with its OIDC identity. The `backend "azurerm" {}`
block in `versions.tf` is **partial** — per-environment values are in
`backends/<env>.hcl`, committed, because the container is protected by RBAC
rather than by obscurity.

A partial backend **prompts** on a plain `terraform init` and fails outright
under `-input=false`, so anything that does not touch state must use
`init -backend=false` — the Makefile's `init`, `validate` and the CI validate
job all do. `terraform console`, unlike `validate`, needs a real backend.

## Environments

`terraform/environments/{dev,stg,prd}.tfvars`; `make plan ENV=<env>` selects
one. **Only `dev` is planned in CI and applied**; CI validates all three. A second
environment would mean a second shared environment for tenants that do not
exist yet. The plumbing is kept so that changing this is a decision rather than
a rebuild. These files are committed intentionally; don't put secrets in them
(`gitleaks` scans as a backstop).

## Commands

```bash
make install   # pre-commit hooks
make lint      # every hook against every file
make fmt       # terraform fmt -recursive
make validate  # terraform init + validate (no Azure credentials)
make plan      # terraform init + plan (ENV=dev|stg|prd, default dev)
make apply     # terraform init + apply (ENV=dev|stg|prd, default dev; dev is applied by running cd-terraform by hand)
make outputs   # print the values a tenant needs
```

## CI

Workflows are prefixed `ci-` (pull-request checks) or `cd-` (post-merge
delivery), and **every one is a thin caller of a reusable workflow in
[`jay-withers/workflows`](https://github.com/jay-withers/workflows)**, pinned by
commit SHA with the tag as a comment. A change to how a job *works* belongs
there so every consuming repo picks it up.

Because they are reusable-workflow calls, status check contexts are namespaced
`<caller job id> / <reusable job name>` rather than the bare job id. **Read
them off `gh pr checks` rather than inferring them.** The required checks —
set in `github-repos`, not here — are `pre-commit / Pre-commit`,
`terraform / Terraform` and `terraform-plan`.

`ci-terraform` calls two shared workflows. `validate` comes from
`terraform.yml` and reports `terraform / Terraform`. `plan` calls
`terraform-deploy.yml` for dev, which also comments the plan on the PR. `terraform.yml` runs no plan, deliberately: in `azure-landingzone` and
`terraform-root-aks` the root modules resolve each other with data sources, and
a plan against a not-yet-applied dependency fails for something that is not a
defect. `terraform-deploy.yml` is the opt-in for configurations like this one
that are self-contained and plan cleanly. Don't move the plan into
`terraform.yml`.

Two consequences: `plan` reuses the shared workflow's path filter via its
`changed` output rather than declaring a second one that would drift, at the
cost of starting after `validate` instead of beside it; and `plan` needs its own
always-reporting gate, `terraform-plan`, because `terraform / Terraform` only
covers what runs inside the shared workflow.

The shared `terraform-deploy.yml` runs its job in the `dev` GitHub
environment. `github-repos` creates that environment and sets
`AZURE_CLIENT_ID`, `AZURE_TENANT_ID` and `AZURE_SUBSCRIPTION_ID` on it, and
federates this repo's OIDC identity to `<repo prefix>:environment:dev` (the
immutable `repo:jay-withers@<id>/azure-container-apps@<id>` form). Callers
pass no credentials and can't gate on those variables, since a calling job
outside the environment can't read them. Don't add a GitHub environment to a
calling job, and don't plan stg or prd here without first federating them in
`github-repos`.

`cd-terraform` **plans dev on merge to main and applies only when run by
hand** (Actions → Run workflow), via the shared `terraform-deploy.yml`. A merge
whose plan has changes opens a `terraform-pending` issue; the manual run
applies exactly the plan it prints and closes it. It runs in the same `dev` environment, and the
identity holds Contributor on `rg-platform-dev` (granted in `github-repos`).
Apply dev by running `cd-terraform`, not with a local `make apply`. `make apply` is
still how stg or prd would be applied, if that is ever decided.

## Commit messages

Conventional Commits, enforced by commitlint at commit-msg time. The
`no-commit-to-branch` pre-commit hook blocks direct commits to `main`.

`cd-tag` mints a semver tag and GitHub release on every merge, regardless of
what changed, with the bump size taken purely from conventional-commit type.

## Repo settings

Branch protection and repository settings are **not** configured here. This
repo is managed by
[jay-withers/github-repos](https://github.com/jay-withers/github-repos), which
is the single source of truth for every jay-withers repo — and whose
`terraform.tfvars` doubles as the catalogue of what each one is for.

The hazard there is the apply, not the rename: applying a required check that
nothing reports leaves every PR *pending* rather than failing it. Check the
contexts against `gh pr checks` output *before* applying.
