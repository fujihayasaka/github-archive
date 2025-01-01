resource "azurerm_storage_account" "turboscan_storage_account" {
  name = "turboscan${replace(coalesce(var.stamp_azure_name, var.stamp_name), "-", "")}"
  resource_group_name = azurerm_resource_group.turboscan_resource_group.name
  location = azurerm_resource_group.turboscan_resource_group.location
  account_kind = "StorageV2"
  account_tier = "Standard"
  access_tier = "Hot"
  account_replication_type = "GZRS"
  min_tls_version = "TLS1_2"
  allow_nested_items_to_be_public = false
  blob_properties {
    container_delete_retention_policy {
      days = 30
    }
    delete_retention_policy {
      days = 30
    }
    versioning_enabled = true
    change_feed_enabled = true
    change_feed_retention_in_days = 30
  }
  tags = {
    catalog_service : "github/code_scanning"
  }
}

resource "azurerm_storage_container" "turboscan_storage_container" {
  name = "sarif-upload"
  storage_account_id = azurerm_storage_account.turboscan_storage_account.id
  container_access_type = "private"
}

resource "azurerm_management_lock" "turboscan_storage_account_lock" {
  name = "turboscan-storage-account-lock"
  scope = azurerm_storage_account.turboscan_storage_account.id
  lock_level = "CanNotDelete"
}

resource "azurerm_storage_management_policy" "turboscan_storage_management_policy" {
  storage_account_id = azurerm_storage_account.turboscan_storage_account.id
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

resource "octovault_application_secret" "storage_account_key" {
  application = "turboscan"
  environment = "${var.stamp_name}"

  key = "AZURE_STORAGE_ACCOUNT_KEY"
  value = "${azurerm_storage_account.turboscan_storage_account.primary_access_key}"
}

resource "octovault_application_secret" "storage_account_name_github" {
  application = "github"
  environment = "${var.stamp_name}"

  key = "TURBOSCAN_AZURE_ACCOUNT_NAME"
  value = "${azurerm_storage_account.turboscan_storage_account.name}"
}

resource "octovault_application_secret" "storage_account_container_github" {
  application = "github"
  environment = "${var.stamp_name}"

  key = "TURBOSCAN_AZURE_CONTAINER"
  value = "${azurerm_storage_container.turboscan_storage_container.name}"
}

resource "octovault_application_secret" "storage_account_key_github" {
  application = "github"
  environment = "${var.stamp_name}"

  key = "TURBOSCAN_AZURE_ACCOUNT_KEY"
  value = "${azurerm_storage_account.turboscan_storage_account.primary_access_key}"
}
