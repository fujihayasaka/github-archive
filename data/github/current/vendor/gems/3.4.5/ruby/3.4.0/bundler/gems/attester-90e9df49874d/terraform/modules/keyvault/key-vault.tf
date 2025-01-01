data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "attester_kv" {
  name                = "Attester-${var.env}"
  resource_group_name = azurerm_resource_group.attester_resource_group.name
  location            = var.resource_location
  # ID of the tenant associated with the subscription, this is always the
  # same since the tenant is Github
  tenant_id = data.azurerm_client_config.current.tenant_id
  tags      = var.project_tags

  # this field needs to be set to an empty array since the key vault will use
  # rbac instead of access policies
  access_policy = []

  enable_rbac_authorization = true

  # limit access to the private endpoint
  public_network_access_enabled = var.public_network_access_enabled

  network_acls {
    bypass         = "None"
    default_action = var.default_action
    ip_rules       = local.ip_rules
  }

  # sku_name must be set to "premium" to enable HSM backed key storage
  sku_name = "premium"
}
