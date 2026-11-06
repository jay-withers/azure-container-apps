variable "project_name" {
  description = "Name included in every resource name here. Tenants resolve the Container Apps environment by name (`cae-<project_name>-<environment>`), so changing this after tenants exist means updating each of them — treat it as fixed once anything has deployed."
  type        = string
  default     = "platform"

  validation {
    # Lowercase only: container app environments, like container apps and jobs,
    # reject uppercase. 15 characters keeps every name here inside its type's
    # limit, the tightest of which is the 32 allowed for the environment.
    condition     = can(regex("^[a-z][a-z0-9]{1,14}$", var.project_name))
    error_message = "project_name must be 2-15 lowercase alphanumeric characters, starting with a letter."
  }
}

variable "location" {
  # Constrained by the `allowed-locations-dev` policy, which denies anything
  # outside westeurope/northeurope. northeurope matches the existing
  # market-agent deployment, which matters: a container app or job may sit in a
  # different resource group from its environment, but not a different region,
  # so this is the region every tenant is bound to.
  description = "Azure region resources are created in. Every tenant workload must be in this same region."
  type        = string
  default     = "northeurope"
}

variable "tags" {
  description = "Tags applied to all resources, merged with (and taking precedence over) the default tags (`environment`, `managed-by`)."
  type        = map(string)
  default     = {}
}

variable "monthly_budget_amount" {
  description = "Monthly Azure spend, in the subscription's billing currency, above which the budget notifies. Nothing here has a standing cost since the shared Postgres server went (2026-11): everything is Consumption-only and inside the Log Analytics free grant. The default dates from when the server billed about 13-17 a month, and still catches a mistake (a workload profile attached by hand, a tenant's runaway logging, a database server) rather than firing every month. Notifications only: Azure budgets never stop anything spending."
  type        = number
  default     = 25

  validation {
    condition     = var.monthly_budget_amount > 0
    error_message = "monthly_budget_amount must be greater than zero."
  }
}

variable "budget_start_date" {
  description = "First day of the budget's first period, which Azure requires to be the first of a month. Ignored after creation — see the `lifecycle` block in `main.alerts.tf` — so it only matters on a fresh apply, and a date in an already-past month is rejected on create."
  type        = string
  default     = "2026-09-01T00:00:00Z"

  validation {
    condition     = can(regex("^\\d{4}-\\d{2}-01T00:00:00Z$", var.budget_start_date))
    error_message = "budget_start_date must be the first of a month, as YYYY-MM-01T00:00:00Z."
  }
}
