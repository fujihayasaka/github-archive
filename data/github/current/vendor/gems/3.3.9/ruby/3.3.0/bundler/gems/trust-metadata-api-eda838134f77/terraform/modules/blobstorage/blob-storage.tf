/*
The storage account is the unique namespace, it's used to address data.
For example, if the storage account name is tmastaging, the URL to access the data is
https://tmastaging.blob.core.windows.net
*/
resource "azurerm_storage_account" "tma_storage_account" {
  # The storage account name can only consist of lowercase letters and numbers
  name                = replace("tma${var.env}", "-", "")
  resource_group_name = azurerm_resource_group.tma_resource_group.name
  location            = azurerm_resource_group.tma_resource_group.location
  account_tier        = "Standard"
  # https://learn.microsoft.com/en-us/azure/storage/common/storage-redundancy
  account_replication_type        = "ZRS"
  shared_access_key_enabled       = false
  # Disallow anonymous public access to blobs, defaults to true(!!!)
  allow_nested_items_to_be_public = false
}

/*
Containers organizes a set of blobs, similar to a directory.
A storage account can hold an unlimited number of containers, and each
container can store an unlimited number of blobs.

Contanier names must be valid DNS name, as they are part of the uniqe
URI to address the container or its blobs. For example, if the container
name is attestations, the URL to access the blobs is
https://tmastaging.blob.core.windows.net/attestations
*/
resource "azurerm_storage_container" "tma_storage_container" {
  name                  = "attestations"
  storage_account_name  = azurerm_storage_account.tma_storage_account.name
  container_access_type = "private"
}
