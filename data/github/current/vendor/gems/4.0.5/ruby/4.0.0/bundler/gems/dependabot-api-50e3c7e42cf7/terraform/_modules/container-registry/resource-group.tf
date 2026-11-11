data "azurerm_resource_group" "dependabot_api_resource_group" {
  name = "dependabot-api-${coalesce(var.stamp_azure_name, var.stamp_name)}"
}