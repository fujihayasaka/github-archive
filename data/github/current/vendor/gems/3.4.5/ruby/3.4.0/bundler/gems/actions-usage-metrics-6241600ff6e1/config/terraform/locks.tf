resource "azurerm_management_lock" "resource_group_prod" {
  depends_on = [module.rg-production]
  name       = "resource-group-prod"
  scope      = module.rg-production.rg_id
  lock_level = "CanNotDelete"
  notes      = "Items cannot be deleted in this resource group."
}

resource "azurerm_management_lock" "resource_group_lab" {
  depends_on = [module.rg-lab]
  name       = "resource-group-lab"
  scope      = module.rg-lab.rg_id
  lock_level = "CanNotDelete"
  notes      = "Items cannot be deleted in this resource group."
}
