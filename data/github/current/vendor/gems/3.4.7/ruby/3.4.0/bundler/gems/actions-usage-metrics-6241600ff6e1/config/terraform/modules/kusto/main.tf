locals {
  githubazure_tenant_id = "398a6654-997b-47e9-b12b-9515b896b4de" // githubazure
}

resource "azurerm_kusto_cluster" "kusto" {
  name                        = var.cluster_name
  resource_group_name         = var.resource_group_name
  auto_stop_enabled           = false
  purge_enabled               = true
  language_extensions         = ["R", "PYTHON"]
  streaming_ingestion_enabled = true
  disk_encryption_enabled     = true

  // Region must match https://github.com/github/terraform-azurerm-data-warehouse/tree/master/sites/ga-dw-prod/dw-kusto-prod
  // to support following DW Kusto
  location = var.region
  zones    = [1, 2, 3]

  sku {
    name = var.sku_name
  }

  optimized_auto_scale {
    minimum_instances = var.auto_scale_minimum_instances
    maximum_instances = var.auto_scale_maximum_instances
  }

  identity {
    type = "SystemAssigned"
  }

  trusted_external_tenants = [
    local.githubazure_tenant_id // GitHubAzure only
  ]

  lifecycle {
    prevent_destroy = true
    ignore_changes = [
      // prevents overriding decisions by autoscaler
      sku[0].capacity,
      optimized_auto_scale
    ]
  }
}

# Configure kusto diagnostics to forward logs and metrics to the log analytics workspace
module "kusto-diagnostics" {
  source                     = "../kusto-diagnostics"
  name                       = "${var.app}-${var.environment}-diagnostics"
  kusto_cluster_id           = azurerm_kusto_cluster.kusto.id
  log_analytics_workspace_id = var.log_analytics_workspace_id
}


resource "azurerm_kusto_cluster_principal_assignment" "service-runtime-reader" {
  for_each            = { for index, spn in var.reader_spn : spn => index }
  name                = each.value == 0 ? "service-runtime-reader" : "service-runtime-reader-${each.value}"
  resource_group_name = var.resource_group_name
  cluster_name        = azurerm_kusto_cluster.kusto.name
  tenant_id           = local.githubazure_tenant_id
  principal_id        = each.key
  principal_type      = "App"
  role                = "AllDatabasesViewer"
}

resource "azurerm_kusto_cluster_principal_assignment" "jit-admin" {
  name                = "jit-admin"
  resource_group_name = var.resource_group_name
  cluster_name        = azurerm_kusto_cluster.kusto.name

  tenant_id      = local.githubazure_tenant_id
  principal_id   = var.jit_group_id
  principal_type = "Group"
  role           = "AllDatabasesAdmin"
}
