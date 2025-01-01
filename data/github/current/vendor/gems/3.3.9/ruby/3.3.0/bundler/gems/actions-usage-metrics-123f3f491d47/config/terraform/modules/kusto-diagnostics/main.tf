resource "azurerm_monitor_diagnostic_setting" "kusto_diagnostic_settings" {
  name                       = var.name
  target_resource_id         = var.kusto_cluster_id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_log {
    category_group = "audit"
  }

  metric {
    category = "AllMetrics"
  }
}
