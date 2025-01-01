// see https://learn.microsoft.com/en-us/azure/azure-monitor/reference/supported-metrics/microsoft-storage-storageaccounts-metrics
// for a list of Azure Blob Storage account metrics

// action group that allows us to send alerts to PagerDuty
resource "azurerm_monitor_action_group" "tma_pagerduty_action_group" {
  name                = "TMA Blob Storage Alert PagerDuty Action"
  resource_group_name = azurerm_resource_group.tma_resource_group.name
  short_name          = "tma-pd-alert"

  webhook_receiver {
    name                    = "package-security-pagerduty-webhook"
    service_uri             = var.pagerduty_integration_url
    use_common_alert_schema = true
  }

  tags = var.project_tags
}

// alert that triggers when the blob storage account availability is below the acceptable threshold
resource "azurerm_monitor_metric_alert" "tma_availability_alert" {
  name                = "TMA Elevated Unavailability"
  resource_group_name = azurerm_resource_group.tma_resource_group.name
  scopes              = [azurerm_storage_account.tma_storage_account.id]
  description         = "Blob Storage average availability has dropped below the set threshold."

  criteria {
    metric_namespace = "Microsoft.Storage/storageAccounts"
    metric_name      = "Availability"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = 98
  }

  // evaluation frequency of the alert
  frequency = "PT1M"
  // period of time that is used to monitor alert activity
  window_size = "PT5M"

  action {
    action_group_id = azurerm_monitor_action_group.tma_pagerduty_action_group.id
  }

  tags = var.project_tags
}

// alert that triggers when the Blob Storage E2E latency is higher
// than the acceptable threshold
resource "azurerm_monitor_metric_alert" "tma_e2e_latency_alert" {
  name                = "TMA Blob Storage E2E Elevated Latency"
  resource_group_name = azurerm_resource_group.tma_resource_group.name
  scopes              = [azurerm_storage_account.tma_storage_account.id]
  description         = "Action will be triggered when elevated e2e latency is reported."

  dynamic_criteria {
    metric_namespace  = "Microsoft.Storage/storageAccounts"
    metric_name       = "SuccessE2ELatency"
    aggregation       = "Average"
    operator          = "GreaterThan"
    alert_sensitivity = "Medium"
  }

  // evaluation frequency of the alert
  frequency = "PT1M"
  // period of time that is used to monitor alert activity
  window_size = "PT5M"

  action {
    action_group_id = azurerm_monitor_action_group.tma_pagerduty_action_group.id
  }

  tags = var.project_tags
}

// alert that triggers when the Blob Storage server latency is higher
// than the acceptable threshold
resource "azurerm_monitor_metric_alert" "tma_server_latency_alert" {
  name                = "TMA Blob Storage Server Elevated Latency"
  resource_group_name = azurerm_resource_group.tma_resource_group.name
  scopes              = [azurerm_storage_account.tma_storage_account.id]
  description         = "Action will be triggered when elevated server latency is reported."

  dynamic_criteria {
    metric_namespace  = "Microsoft.Storage/storageAccounts"
    metric_name       = "SuccessServerLatency"
    aggregation       = "Average"
    operator          = "GreaterThan"
    alert_sensitivity = "Medium"
  }

  // evaluation frequency of the alert
  frequency = "PT1M"
  // period of time that is used to monitor alert activity
  window_size = "PT5M"

  action {
    action_group_id = azurerm_monitor_action_group.tma_pagerduty_action_group.id
  }

  tags = var.project_tags
}

resource "azurerm_monitor_activity_log_alert" "privileged_role_assignment_alert" {
  name                = "Privileged Azure Role Assignment Alert"
  resource_group_name = azurerm_resource_group.tma_resource_group.name
  scopes              = [azurerm_resource_group.tma_resource_group.id]
  description         = "Action will be triggered when privileged Azure role assignments are made."

  criteria {
    operation_name = "Microsoft.Authorization/roleAssignments/write"
    category       = "Administrative"
    status         = "Succeeded"
  }

  action {
    action_group_id = azurerm_monitor_action_group.tma_pagerduty_action_group.id
  }

  tags = var.project_tags
}
