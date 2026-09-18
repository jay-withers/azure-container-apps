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

variable "alert_email_address" {
  description = "Address added to the alert action group as an email receiver, alongside the ARM role receiver that reaches whoever holds `Owner` on the subscription. Committed deliberately: this repository is public, so an address here is permanent in its history — an address is an identifier rather than a credential. Set it empty to send to the Owner role alone, or override with `TF_VAR_alert_email_address` to keep a different address out of git."
  type        = string
  default     = "withersj888@outlook.com"

  validation {
    # Printable ASCII either side of the `@`. A curly quote pasted from
    # somewhere that autocorrects is invisible in most output and has already
    # cost the market-agent project one day's summary email.
    condition     = var.alert_email_address == "" || can(regex("^[!-?A-~]+@[!-?A-~]+\\.[!-?A-~]+$", var.alert_email_address))
    error_message = "alert_email_address must be empty or a plain-ASCII email address."
  }
}

variable "monthly_budget_amount" {
  description = "Monthly Azure spend, in the subscription's billing currency, above which the budget notifies. This configuration has no standing cost at all — no database, no workload profile, and everything inside the Log Analytics free grant — so the default is a low ceiling chosen to notice a mistake (a workload profile attached by hand, a tenant's runaway logging) rather than to accommodate normal operation. Notifications only: Azure budgets never stop anything spending."
  type        = number
  default     = 5

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
