terraform {
  backend "remote" {
    hostname     = "terraform.githubapp.com"
    organization = "azure-dsp-dependency-graph-prod"
    workspaces {
      name = "dependency-snapshots-api-prod-sdc-01"
    }
  }
}

resource "azurerm_resource_group" "ds" {
  name     = "dsapi-prod-sdc-01"
  location = "swedencentral"
}

resource "azurerm_storage_account" "ds" {
  name                     = "ghdsapiprodsdc01"
  resource_group_name      = azurerm_resource_group.ds.name
  location                 = azurerm_resource_group.ds.location
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "GZRS"
  allow_nested_items_to_be_public = false
  min_tls_version          = "TLS1_2"
  shared_access_key_enabled = false
}

resource "azurerm_storage_container" "ds" {
  name                 = "snapshot-blobs"
  storage_account_name = azurerm_storage_account.ds.name
}
