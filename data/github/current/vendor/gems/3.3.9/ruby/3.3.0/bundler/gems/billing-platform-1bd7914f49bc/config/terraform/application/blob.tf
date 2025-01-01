module "storage_rg" {
  source  = "terraform.githubapp.com/azure-data-patterns-and-scaling/github-cosmos/azurerm//modules/azure-resource-group"
  version = "0.1.1" # Be sure to use the latest version you can

  team_prefix   = local.team_prefix
  region        = var.primary_regions[var.stamp_name].location
  name_override = var.storage_account_rg_name
}

resource "azurerm_storage_account" "metered_billing_storage_account" {
  name                             = var.storage_account_name
  location                         = var.primary_regions[var.stamp_name].location
  resource_group_name              = module.storage_rg.rg_name
  account_kind                     = "StorageV2"
  account_tier                     = "Standard"
  allow_nested_items_to_be_public  = false
  cross_tenant_replication_enabled = false
  account_replication_type         = "RAGRS"
  https_traffic_only_enabled        = true
  min_tls_version                  = "TLS1_2"
  shared_access_key_enabled        = false
  tags = {
    catalog_service : "github/metered_billing_spend_management"
  }
}

resource "azurerm_storage_container" "billing-metered-exports-reports" {
  name                  = "billing-metered-exports-reports"
  storage_account_name  = azurerm_storage_account.metered_billing_storage_account.name
  container_access_type = "private"
}
