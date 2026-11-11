resource "azurerm_container_registry" "container_registry" {
  name                = "dependabotapi${replace(coalesce(var.stamp_azure_name, var.stamp_name), "-", "")}"
  resource_group_name = data.azurerm_resource_group.dependabot_api_resource_group.name
  location            = var.stamp_azure_region
  sku                 = "Premium"
  
  admin_enabled                 = false
  public_network_access_enabled = var.acr_public_network_access == "Enabled" ? true : false
  anonymous_pull_enabled        = false
  network_rule_bypass_option    = "AzureServices"

  identity {
    type = "SystemAssigned"
  }

  retention_policy_in_days = 7
  trust_policy_enabled = false

  tags = {
    catalog_service : "github/dependabot-api"
  }
}

resource "azurerm_container_registry_cache_rule" "cache_rule" {
  name                  = "dependabot-cache-rule"
  container_registry_id = azurerm_container_registry.container_registry.id
  source_repo           = var.acr_cache_source_repo
  target_repo           = var.acr_cache_target_repo
}
