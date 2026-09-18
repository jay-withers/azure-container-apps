variable "environment" {
  description = "Deployment environment. Drives resource naming, and is part of the environment name tenants resolve by."
  type        = string

  validation {
    condition     = contains(["dev", "stg", "prd"], var.environment)
    error_message = "environment must be one of: dev, stg, prd."
  }
}
