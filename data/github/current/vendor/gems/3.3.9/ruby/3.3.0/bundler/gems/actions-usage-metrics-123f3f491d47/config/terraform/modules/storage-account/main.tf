locals {
  githubazure_tenant_id = "398a6654-997b-47e9-b12b-9515b896b4de" // githubazure
}

# Storage Account
resource "azurerm_storage_account" "storage_account" {
  name                      = var.account_name
  resource_group_name       = var.resource_group_name
  location                  = var.region
  account_tier              = "Standard"
  account_replication_type  = "ZRS"
  account_kind              = "StorageV2"
  is_hns_enabled            = true // Hierarchical namespace needed for setting expiry time on blobs
  shared_access_key_enabled = false
  allow_nested_items_to_be_public  = false // false disabled anonymous access
}

# Containers
resource "azurerm_storage_container" "export_container" {
  name                  = "export"
  storage_account_name  = azurerm_storage_account.storage_account.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "export_status_container" {
  name                  = "export-status"
  storage_account_name  = azurerm_storage_account.storage_account.name
  container_access_type = "private"
}

# Management policies
resource "azurerm_storage_management_policy" "management_policies" {
  storage_account_id = azurerm_storage_account.storage_account.id

  rule {
    name    = "ttl-export"
    enabled = true
    filters {
      prefix_match = ["export"]
      blob_types   = ["blockBlob", "appendBlob"]
    }
    actions {
      base_blob {
        delete_after_days_since_modification_greater_than = 1
      }
    }
  }
}

# Diagnostics
resource "azurerm_monitor_diagnostic_setting" "storage_account_diagnostic_settings" {
  name                       = "${var.app}-${var.environment}-diagnostics"
  target_resource_id         = azurerm_storage_account.storage_account.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  metric {
    category = "Transaction"
  }
}


resource "azurerm_monitor_diagnostic_setting" "blob_service_diagnostic_settings" {
  name                       = "${var.app}-${var.environment}-diagnostics"
  target_resource_id         = "${azurerm_storage_account.storage_account.id}/blobServices/default"
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_log {
    category_group = "audit"
  }

  metric {
    category = "Transaction"
  }
}
