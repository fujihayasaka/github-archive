resource "azurerm_resource_group" "turboscan_resource_group" {
  name = "turboscan-${coalesce(var.stamp_azure_name, var.stamp_name)}"
  location = var.stamp_azure_region
  tags = {
    catalog_service : "github/code_scanning"
  }
}
