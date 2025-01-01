resource "azurerm_log_analytics_workspace" "tma_analytics_workspace" {
  name                = "TMA-${title(var.env)}"
  location            = azurerm_resource_group.tma_resource_group.location
  resource_group_name = azurerm_resource_group.tma_resource_group.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_log_analytics_storage_insights" "tma_storage_insights" {
  name                = "TMA-${title(var.env)}-Blob-Storage"
  resource_group_name = azurerm_resource_group.tma_resource_group.name
  workspace_id        = azurerm_log_analytics_workspace.tma_analytics_workspace.id

  storage_account_id  = azurerm_storage_account.tma_storage_account.id
  storage_account_key = azurerm_storage_account.tma_storage_account.primary_access_key
}
