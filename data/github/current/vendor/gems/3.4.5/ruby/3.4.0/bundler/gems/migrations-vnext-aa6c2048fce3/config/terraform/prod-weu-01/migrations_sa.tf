# Create a paved path storage account
module "storage_account" {
  source  = "terraform.githubapp.com/azure-object-storage/github-blob-storage/azurerm"
  version = "0.0.13"

  resource_group = {
    name = azurerm_resource_group.rg.name
    id   = azurerm_resource_group.rg.id
  }
  location                       = azurerm_resource_group.rg.location
  team_prefix                    = "mvn"
  catalog_service                = "github/migrations-vnext"
  environment_type               = "production"
  stamp                          = var.vaultenv
  data_classification            = "confidential"
  storage_container_names        = ["payloads"]
  network_default_action         = "Allow" # Allow is the default setting we already have, but we will need to lock this down in the future after setting up private links
  default_logs_analytics_enabled = false   # Keeping this false at first as we move to paved path, but we can allow this to be created later
}