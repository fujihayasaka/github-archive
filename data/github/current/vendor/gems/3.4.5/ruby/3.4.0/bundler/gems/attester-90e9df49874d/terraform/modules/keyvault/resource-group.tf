resource "azurerm_resource_group" "attester_resource_group" {
  name     = "Attester-${var.env}"
  location = var.resource_location
  tags     = var.project_tags
}
