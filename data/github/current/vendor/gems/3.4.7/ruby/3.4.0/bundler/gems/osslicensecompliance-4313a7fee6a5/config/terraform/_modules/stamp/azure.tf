# Setup Azure Resource Group
resource "azurerm_resource_group" "olc_resource_group" {
  name     = "olc-${var.stamp_name}"
  location = var.stamp_azure_region
  tags = {
    catalog_service : "github/osslicensecompliance"
  }
}

# Provision Azure Storage Account
resource "azurerm_storage_account" "olc_storage_account" {
  name                            = "olc${replace(var.stamp_name, "-", "")}"
  resource_group_name             = azurerm_resource_group.olc_resource_group.name
  location                        = azurerm_resource_group.olc_resource_group.location
  account_kind                    = "BlockBlobStorage"
  account_tier                    = "Premium"
  account_replication_type        = "ZRS"
  allow_nested_items_to_be_public = false
  min_tls_version                 = "TLS1_2"
  shared_access_key_enabled       = false
  blob_properties {
    versioning_enabled = true
  }
  tags = {
    catalog_service : "github/osslicensecompliance"
  }
}

# Policy to delete old versions when 30 days old
resource "azurerm_storage_management_policy" "olc_lifecycle_policy" {
  storage_account_id = azurerm_storage_account.olc_storage_account.id

  rule {
    name    = "delete_old_license_policy_versions"
    enabled = true
    filters {
      blob_types = ["blockBlob"]
    }
    actions {
      version {
        delete_after_days_since_creation = 30
      }
    }
  }
}

# Provision Azure Storage Container for repo policies
resource "azurerm_storage_container" "olc-repository-policies" {
  name                  = "repository-policies"
  storage_account_name  = azurerm_storage_account.olc_storage_account.name
  container_access_type = "private"
}

# Provision Azure Storage Container for org policies
resource "azurerm_storage_container" "olc-organization-policies" {
  name                  = "organization-policies"
  storage_account_name  = azurerm_storage_account.olc_storage_account.name
  container_access_type = "private"
}

# Provision Azure Storage Container for enterprise policies
resource "azurerm_storage_container" "olc-enterprise-policies" {
  name                  = "enterprise-policies"
  storage_account_name  = azurerm_storage_account.olc_storage_account.name
  container_access_type = "private"
}
