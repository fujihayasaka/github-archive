locals {
  cluster_name = "ghbillingprod"
  sku_name     = "Standard_L16as_v3"
}

resource "azurerm_kusto_cluster" "kusto" {
  name                        = local.cluster_name
  resource_group_name         = local.data_resource_group_name
  auto_stop_enabled           = false
  purge_enabled               = true
  streaming_ingestion_enabled = true

  // Region must match https://github.com/github/terraform-azurerm-data-warehouse/tree/master/sites/ga-dw-prod/dw-kusto-prod
  // to support following DW Kusto
  location = "eastus"
  zones    = [1, 2, 3]

  sku {
    name = local.sku_name
  }

  optimized_auto_scale {
    minimum_instances = 2
    maximum_instances = 10
  }

  identity {
    type = "SystemAssigned"
  }

  trusted_external_tenants = [
    "398a6654-997b-47e9-b12b-9515b896b4de" // GitHubAzure only
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

resource "azurerm_kusto_cluster_principal_assignment" "service-runtime-reader" {
  name                = "service-runtime-reader"
  resource_group_name = local.data_resource_group_name
  cluster_name        = azurerm_kusto_cluster.kusto.name

  tenant_id      = "398a6654-997b-47e9-b12b-9515b896b4de" // githubazure
  principal_id   = "8303599c-6a32-4332-9398-24724082cecf" // reader_spn
  principal_type = "App"
  role           = "AllDatabasesViewer"
}

resource "azurerm_kusto_cluster_principal_assignment" "billingplatform-contributor" {
  name                = "billingplatform-contributor"
  resource_group_name = local.data_resource_group_name
  cluster_name        = azurerm_kusto_cluster.kusto.name

  tenant_id      = "398a6654-997b-47e9-b12b-9515b896b4de" // githubazure
  principal_id   = "84225277-e5de-4e8e-9500-60001fae8c3c" // azure-github-prod-pande-billingplatform-contributor
  principal_type = "Group"
  role           = "AllDatabasesViewer"
}

resource "azurerm_kusto_cluster_principal_assignment" "spn-billing-platform-kusto" {
  name                = "spn-billing-platform-kusto"
  resource_group_name = local.data_resource_group_name
  cluster_name        = azurerm_kusto_cluster.kusto.name

  tenant_id      = "398a6654-997b-47e9-b12b-9515b896b4de" // githubazure
  principal_id   = "f6549ff9-bbe7-4711-92a0-96ef3771129c" // spn-billing_platform_kusto_prod
  principal_type = "App"
  role           = "AllDatabasesAdmin"
}
