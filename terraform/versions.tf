terraform {
  required_version = ">= 1.6"

  # Partial: per-environment values live in backends/<env>.hcl.
  #   terraform init -backend-config=backends/dev.hcl
  # Anything not touching state must init with -backend=false, or this prompts.
  backend "azurerm" {}

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.0"
    }
    # Transitive dependency of module.naming, declared so the provider footprint
    # is visible.
    random = {
      source  = "hashicorp/random"
      version = ">= 3.3.2"
    }

    # Only for the Aspire Dashboard dotnet component: azurerm has no resource
    # for it (hashicorp/terraform-provider-azurerm#28187, still open), so it's
    # managed as a raw ARM call instead. Remove this the day that issue ships.
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.0"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      # False on purpose: with this true, `terraform destroy` fails whenever
      # Azure has parked anything in the group that Terraform doesn't manage.
      prevent_deletion_if_contains_resources = false
    }
  }

  use_oidc = true
}

provider "azapi" {
  use_oidc = true
}
