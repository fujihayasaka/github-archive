# This template exists for convenience to test template updates in
# our NON-PROD Subscription. As of today, Azure Blob Store is using
# an emulator locally (azurite).

# Terraform App can be accessed via Okta
# Reference: https://www.terraform.io/docs/language/settings/backends/remote.html
terraform {
  backend "remote" {
    hostname     = "terraform.githubapp.com"
    organization = "azure-dsp-dependency-graph-prod"
    workspaces {
      name = "dependency-snapshots-api"
    }
  }
}

# Docs Reference: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs

# create Azure resource group
resource "azurerm_resource_group" "ds" {
  name     = "ds-api-production"
  location = var.region
}

resource "azurerm_storage_account" "ds" {
  name                               = "proddssnapshotsstorage"
  resource_group_name                = azurerm_resource_group.ds.name
  location                           = azurerm_resource_group.ds.location
  account_kind                       = "BlockBlobStorage"
  account_tier                       = "Premium"
  account_replication_type           = "ZRS"
  allow_nested_items_to_be_public    = false
  min_tls_version                    = "TLS1_2"
  shared_access_key_enabled          = false
  cross_tenant_replication_enabled   = false
  https_traffic_only_enabled         = true
  large_file_share_enabled           = false
  local_user_enabled                 = true
  dns_endpoint_type                  = "Standard"
}

# create the containers
resource "azurerm_storage_container" "ds" {
  count                = var.containers != null ? length(var.containers) : 0
  name                 = var.containers[count.index]
  storage_account_name = azurerm_storage_account.ds.name
}
