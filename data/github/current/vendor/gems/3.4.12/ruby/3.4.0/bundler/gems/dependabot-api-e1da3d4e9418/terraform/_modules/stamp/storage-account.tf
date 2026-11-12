resource "azurerm_storage_account" "dependabot_api_storage_account" {
  name = "dependabotapi${replace(coalesce(var.stamp_azure_name, var.stamp_name), "-", "")}"
  resource_group_name = azurerm_resource_group.dependabot_api_resource_group.name
  location = azurerm_resource_group.dependabot_api_resource_group.location
  account_kind = "StorageV2"
  account_tier = "Standard"
  access_tier = "Hot"
  account_replication_type = var.stamp_replication_type
  https_traffic_only_enabled = true
  min_tls_version = "TLS1_2"
  allow_nested_items_to_be_public = false
  blob_properties {
    container_delete_retention_policy {
      days = 2
    }
    delete_retention_policy {
      days = 2
    }
    versioning_enabled = true
    change_feed_enabled = true
    change_feed_retention_in_days = 30
  }
  tags = {
    catalog_service : "github/dependabot-api"
  }
}

resource "azurerm_storage_container" "dependabot_api_storage_container" {
  name = "dependabot-api-pr-artifacts-upload"
  storage_account_id = azurerm_storage_account.dependabot_api_storage_account.id
  container_access_type = "private"
}

resource "azurerm_management_lock" "dependabot_api_storage_account_lock" {
  name = "dependabot-api-storage-account-lock"
  scope = azurerm_storage_account.dependabot_api_storage_account.id
  lock_level = "CanNotDelete"
}

resource "azurerm_storage_management_policy" "dependabot_api_storage_management_policy" {
  storage_account_id = azurerm_storage_account.dependabot_api_storage_account.id
  rule {
    name = "delete-old-versions"
    enabled = true
    actions {
      version {
        delete_after_days_since_creation = 30
      }
    }
    filters {
      blob_types = ["blockBlob"]
    }
  }
}
