# For the tenant ID on the Postgres server's Entra configuration only. Never
# for an object ID: that would be "whoever applies", which moves to the
# pipeline identity on every cd-terraform run.
data "azurerm_client_config" "current" {}
