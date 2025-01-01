// defines an analytics workspace for Attester related service logs
resource "azurerm_log_analytics_workspace" "attester" {
  name                = "Attester-${var.env}"
  resource_group_name = azurerm_resource_group.attester_resource_group.name
  location            = var.resource_location
}

// enables logging for the Key Vault
resource "azurerm_monitor_diagnostic_setting" "attester_key_vault" {
  name               = "Attester-${var.env} Key Vault Diagnostic Settings"
  target_resource_id = azurerm_key_vault.attester_kv.id

  log_analytics_workspace_id = azurerm_log_analytics_workspace.attester.id

  enabled_log {
    // AuditEvent is the only available value for Key Vault
    category = "AuditEvent"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}
