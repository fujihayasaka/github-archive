# This template exists for convenience to test template updates in
# our NON-PROD Subscription. As of today, Azure Blob Store is using
# an emulator locally (azurite).

# UPDATED 6/2023: using non-TFE managed dev setup for CosmosDB too, so this is STILL NOT USED!
# For dev/CI CosmosDB, you can visit the Azure Portal (remember to JIT and sign in as `<github_handle>@githubazure.com`!)
# Non-Prod development CosmosDB resource:
# https://portal.azure.com/#@githubazure.onmicrosoft.com/resource/subscriptions/bf2356ad-9fb5-427d-8070-63c26283d1ae/resourcegroups/dsapi-development/providers/Microsoft.DocumentDB/databaseAccounts/dsapi-cosmosdb-dev

# Terraform App can be accessed via Okta
# Reference: https://www.terraform.io/docs/language/settings/backends/remote.html
terraform {
  backend "remote" {
    hostname     = "terraform.githubapp.com"
    organization = "azure-dsp-dependency-graph-non-prod"
    workspaces {
      name = "dev-dependency-snapshots-api"
    }
  }
}

# Docs Reference: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs

# create Azure resource group
resource "azurerm_resource_group" "ds" {
  name     = "ds-api-development"
  location = var.region
}

resource "azurerm_storage_account" "ds" {
  name                     = "devdssnapshotsstorage"
  resource_group_name      = azurerm_resource_group.ds.name
  location                 = azurerm_resource_group.ds.location
  account_kind             = "BlockBlobStorage"
  account_tier             = "Premium"
  account_replication_type = "LRS"
  allow_nested_items_to_be_public = false
  min_tls_version          = "TLS1_2"
  shared_access_key_enabled = false
}

# create the containers
resource "azurerm_storage_container" "ds" {
  count                = var.containers != null ? length(var.containers) : 0
  name                 = var.containers[count.index]
  storage_account_name = azurerm_storage_account.ds.name
}
