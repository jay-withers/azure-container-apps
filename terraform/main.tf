# This configuration is the shared half of a two-part split: it owns the
# Container Apps environment and the observability stack that every project
# deploys onto, and nothing else. Key Vaults, managed identities, databases and
# the workloads themselves belong to the project that needs them, in that
# project's own repository and resource group.
#
# The boundary is deliberate. A tenant can be created, changed and destroyed
# without touching this configuration, and its secrets live in a vault no other
# tenant's identity can read.
#
# Deliberately `.name`, not `.name_unique`: names are deterministic, with no
# random suffix. Tenants resolve the environment by name (see README), so a
# random suffix here would make that convention unusable.
module "naming" {
  # checkov:skip=CKV_TF_1: Terraform Registry module pinned by semver
  # (version below), not a git source — there's no commit hash to pin.
  source  = "Azure/naming/azurerm"
  version = "~> 0.4"
  suffix  = [var.project_name, var.environment]
}

resource "azurerm_resource_group" "this" {
  name     = module.naming.resource_group.name
  location = var.location
  tags     = local.tags
}
