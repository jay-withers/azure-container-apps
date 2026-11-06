variable "environment" {
  description = "Deployment environment. Drives resource naming, and is part of the environment name tenants resolve by."
  type        = string

  validation {
    condition     = contains(["dev", "stg", "prd"], var.environment)
    error_message = "environment must be one of: dev, stg, prd."
  }
}

variable "alert_email_address" {
  description = "Address added to the alert action group as an email receiver, alongside the ARM role receiver that reaches whoever holds `Owner` on the subscription. Set it empty to send to the Owner role alone. Not committed: CI reads it from the TF_VAR_ALERT_EMAIL_ADDRESS variable github-repos sets on the `dev` environment; a local plan needs TF_VAR_alert_email_address exported."
  type        = string

  validation {
    # Printable ASCII either side of the `@`. A curly quote pasted from
    # somewhere that autocorrects is invisible in most output and has already
    # cost the market-agent project one day's summary email.
    condition     = var.alert_email_address == "" || can(regex("^[!-?A-~]+@[!-?A-~]+\\.[!-?A-~]+$", var.alert_email_address))
    error_message = "alert_email_address must be empty or a plain-ASCII email address."
  }
}
