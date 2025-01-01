# Create a resource group
resource "azurerm_resource_group" "licensing" {
  name     = "licensing-${var.stamp == "dotcom" ? "production" : var.stamp}"
  location = var.location
  tags = {
    catalog_service : "github/licensing"
  }
}

# Create a paved path storage account
module "storage_account" {
  source  = "terraform.githubapp.com/azure-object-storage/github-blob-storage/azurerm"
  version = "0.0.13"

  resource_group = {
    name = azurerm_resource_group.licensing.name
    id   = azurerm_resource_group.licensing.id
  }
  location                       = azurerm_resource_group.licensing.location
  team_prefix                    = "licensing"
  catalog_service                = "github/licensing"
  environment_type               = "production"
  stamp                          = var.stamp
  data_classification            = "confidential"
  storage_container_names        = ["licensing-ghes-keypairs", "licensing-ghes-server-keys"]
  storage_account_name_override  = var.storage_account_name # New stamps should not set this var so it uses paved path defaults
  network_default_action         = "Allow"                  # Allow is the default setting we already have, but we will need to lock this down in the future after setting up private links
  default_logs_analytics_enabled = false                    # Keeping this false at first as we move to paved path, but we can allow this to be created later
}

# We need to tell terraform that the resources have moved from our old definite to the module definition
# We should only need this for the first deploy to each terraform workspace then it can be deleted
moved {
  from = azurerm_storage_account.licensing_storage_account
  to   = module.storage_account.module.blob_storage_account.azurerm_storage_account.blob_storage_account
}

moved {
  from = azurerm_storage_account_network_rules.licensing_storage_account_network_rules
  to   = module.storage_account.module.blob_storage_network.azurerm_storage_account_network_rules.storage_account_network_rules
}

moved {
  from = azurerm_storage_container.ghes_keypairs_storage_container
  to   = module.storage_account.module.blob_storage_container["licensing-ghes-keypairs"].azurerm_storage_container.storage_container
}

moved {
  from = azurerm_storage_container.ghes_server_keys_storage_container
  to   = module.storage_account.module.blob_storage_container["licensing-ghes-server-keys"].azurerm_storage_container.storage_container
}
