# azure-container-apps

A shared Azure Container Apps environment that any project can deploy onto.

This repository owns the environment and the observability behind it, and
nothing else. It has **no standing cost**: no database, no container registry,
no workload profile, and all ingestion inside the Log Analytics free grant. An
environment with nothing deployed to it bills nothing.

## What is shared, and what is not

| | Owned here | Owned by each project |
|---|---|---|
| Container Apps environment | yes | |
| Log Analytics workspace | yes | |
| Application Insights | yes | |
| Job-failure and log-quota alerts | yes | |
| Resource group | for the above | its own |
| Key Vault | | its own |
| Managed identity | | its own |
| Container apps and jobs | | its own |
| Databases, storage, anything else | | its own |

The split is deliberate. A project can be created, changed and destroyed without
touching this repository, and its secrets sit in a vault no other project's
identity can read.

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

Two rules, both log queries against the shared workspace.

**Job failure.** Fires when any job on the environment emits `ContainerCrashing`,
`BackoffLimitExceeded` or `StartError` — a container that never started, which
is the one failure a project's own code can never report, because none of it
ran. Split by `JobName_s`, so a project added later is covered with no change
here, and one job already failing does not mask a second.

It is a log query rather than a metric alert on `Executions` deliberately: the
metric alert was tried in market-agent and verified on 2026-09-18 not to fire,
despite a real failed execution holding the metric above the threshold well
inside the evaluation window.

**Log quota.** The 0.15 GB/day cap is shared. Reaching it stops ingestion for
every project for the rest of the day — including the job-failure rule above,
which reads logs. Evaluated hourly.

**Known gap:** a schedule that silently never fires emits no log, so nothing
here catches it. A project's own output going missing is the only signal, which
is a good reason for a scheduled job to report something on every run even when
it has nothing to say.

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

az storage container create \
  --name azure-container-apps \
  --account-name sttfsharedjw \
  --auth-mode login
```

`Microsoft.App` genuinely needs this — the environment fails with
`MissingSubscriptionRegistration` on a subscription where it has never been
registered.

Then `make plan ENV=dev` and `make apply ENV=dev`.

## Environments

`terraform/environments/{dev,stg,prd}.tfvars` are the per-environment inputs.
All three are planned in CI; **only `dev` is applied**. The plumbing is kept so
that changing this is a decision rather than a rebuild.

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

```bash
make install    # pre-commit hooks
make lint       # every hook against every file
make fmt        # terraform fmt -recursive
make validate   # init + validate, no Azure credentials
make plan       # init + plan     (ENV=dev|stg|prd, default dev)
make apply      # init + apply    (ENV=dev|stg|prd, default dev)
make outputs    # the values a project needs to point at this environment
```

Generated input/output reference: [`terraform/README.md`](terraform/README.md).
