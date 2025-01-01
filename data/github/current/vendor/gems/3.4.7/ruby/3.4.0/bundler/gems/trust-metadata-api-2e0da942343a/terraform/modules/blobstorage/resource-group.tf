resource "azurerm_resource_group" "tma_resource_group" {
  name     = "TMA-${title(var.env)}"
  location = var.resource_location
  tags     = var.project_tags
}
