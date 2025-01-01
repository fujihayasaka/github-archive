terraform {
  cloud {
    hostname     = "terraform.githubapp.com"
    organization = "azure-licensing"

    workspaces {
      name = "licensing-prod"
    }
  }
}

locals {
  vault_application   = "licensify"
  vault_environment   = "production"
  rg_name             = "licensify-production"
  cosmos_account_name = "licensify"
}

module "fetch_secrets" {
  source = "../fetch-secrets"

  providers = {
    octovault = octovault
  }

  vault_application    = local.vault_application
  vault_environment    = local.vault_environment
  catalog_service_name = "licensing_prod"
}

provider "azurerm" {
  storage_use_azuread = true
  features {}
  client_secret   = module.fetch_secrets.service_principal_client_secret
  tenant_id       = module.fetch_secrets.service_principal_tenant_id
  client_id       = module.fetch_secrets.service_principal_client_id
  subscription_id = "ff6a70fc-0a30-4bf2-a717-6e53896ff59f"
}

module "application" {
  source = "../application"

  providers = {
    azurerm   = azurerm
    octovault = octovault
  }

  vault_application            = local.vault_application
  vault_environment            = local.vault_environment
  rg_name_override             = "licensify-production"
  stamp_name                   = "dotcom"
  allow_gh_dcs                 = true
  cosmos_account_name_override = "licensify"
}

resource "azurerm_cosmosdb_sql_container" "licensify" {
  depends_on          = [module.application]
  resource_group_name = local.rg_name
  account_name        = local.cosmos_account_name
  database_name       = "licensify"
  name                = "licensify"
  partition_key_path  = "/partitionKey"
  default_ttl         = -1
}

# Create resources for Azure blob storage
# Storage account names must be unique across Azure https://learn.microsoft.com/en-us/azure/storage/common/storage-account-overview?toc=%2Fazure%2Fstorage%2Fblobs%2Ftoc.json#storage-account-name
module "azure_blob_storage_production" {
  source = "../azure-blob-storage"

  stamp                = "dotcom"
  location             = "eastus"
  storage_account_name = "licensingproduction"
}
