resource "azurerm_key_vault_key" "attester-leaf-2024-10" {
  name         = "attester-2024-10"
  key_vault_id = azurerm_key_vault.attester_kv.id
  curve        = "P-256"
  key_type     = "EC-HSM"

  key_opts = [
    "sign",
    "verify",
  ]
}
