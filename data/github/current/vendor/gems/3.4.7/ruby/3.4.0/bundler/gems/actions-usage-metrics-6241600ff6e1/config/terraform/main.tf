locals {
  subscription_id = "3cae2114-1f62-430d-9a16-a29bff6024a5"
}

terraform {
  cloud {
    hostname     = "terraform.githubapp.com"
    organization = "actions-fusion"

    workspaces {
      name = "actions-usage-metrics"
    }
  }
}


data "vault_generic_secret" "vault" {
  path = "secret-kv2/apps/actions-usage-metrics/_production"
}

provider "vault" {}
provider "octovault" {}
provider "azurerm" {
  features {}
  client_id           = data.vault_generic_secret.vault.data["spn_actions_usage_metrics_tf_client_id"]
  client_secret       = data.vault_generic_secret.vault.data["spn_actions_usage_metrics_tf"]
  tenant_id           = data.vault_generic_secret.vault.data["spn_actions_usage_metrics_tf_tenant_id"]
  subscription_id     = local.subscription_id
  storage_use_azuread = true
}

locals {
  // Region must match https://github.com/github/terraform-azurerm-data-warehouse/tree/master/sites/ga-dw-prod/dw-kusto-prod
  // to support following DW Kusto
  region                            = "eastus"
  app                               = "actions-usage-metrics"
  jit_group_id                      = "4dda66f0-482c-431f-b33f-6eaefc1f26d0" // azure-actions-usage-metrics-prod-contributor-jit
  runtime_service_principal_id_prod = "74c68fd3-98c4-4103-b13e-d8406a03ed81" // https://github.com/github/azure-rbac/blob/main/tf/rbac/spn-actions-usage-metrics-prod.tf
  runtime_service_principal_id_lab  = "05efb366-59cf-4ff4-9c08-6c37081048c0" // https://github.com/github/azure-rbac/blob/main/tf/rbac/spn-actions-usage-metrics-lab.tf
  ci_service_principal_id           = "98ad5ef2-064e-4b9f-9d46-9035e67f5ca1"
  kusto_cluster_sku_name            = "Standard_L32as_v3"
  stamps = [
    tomap({
      "stamp"  = "prod-ae-01"
      "spn_id" = "d6861010-57f0-4010-8046-b6fb08b379e8"
      "region" = "australiaeast"
    }),
    tomap({
      "stamp"  = "prod-sdc-01"
      "spn_id" = "65637d33-3887-4465-8cca-1abc40202cb2"
      "region" = "swedencentral"
    }),
    tomap({
      "stamp"  = "prod-weu-01"
      "spn_id" = "06ccb19f-c850-495e-b569-d701068e3b86"
      "region" = "westeurope"
    }),
    tomap({
      "stamp"  = "staff-wus2-01"
      "spn_id" = "a58252a8-0abd-4223-ba6e-fd53673a1256"
      "region" = "westus2"
    })
  ]
}

### Production
# RG
module "rg-production" {
  source  = "terraform.githubapp.com/azure-data-patterns-and-scaling/github-cosmos/azurerm//modules/azure-resource-group"
  version = "0.1.2" # Be sure to use the latest version you can

  team_prefix   = local.app
  region        = local.region
  name_override = "${local.app}-production"
}

# Log Analytics
module "log-analytics-workspace-production" {
  source              = "./modules/log-analytics-workspace"
  name                = "${local.app}-production-log-analytics"
  region              = local.region
  resource_group_name = module.rg-production.rg_name
}

# Kusto
module "kusto-production" {
  source = "./modules/kusto"

  // Different naming convention as 22-char max length
  cluster_name                 = "ghaumprod"
  environment                  = "production"
  region                       = local.region
  resource_group_name          = module.rg-production.rg_name
  reader_spn                   = toset([local.runtime_service_principal_id_prod])
  sku_name                     = local.kusto_cluster_sku_name
  auto_scale_minimum_instances = 12
  auto_scale_maximum_instances = 24
  app                          = local.app
  log_analytics_workspace_id   = module.log-analytics-workspace-production.log_analytics_workspace_id
  jit_group_id                 = local.jit_group_id
}

# Storage Account
module "storage-account-production" {
  source = "./modules/storage-account"

  account_name               = "actionsmetricsproduction"
  region                     = local.region
  resource_group_name        = module.rg-production.rg_name
  app                        = local.app
  environment                = "production"
  log_analytics_workspace_id = module.log-analytics-workspace-production.log_analytics_workspace_id
}

### Lab
# RG
module "rg-lab" {
  source  = "terraform.githubapp.com/azure-data-patterns-and-scaling/github-cosmos/azurerm//modules/azure-resource-group"
  version = "0.1.2" # Be sure to use the latest version you can

  team_prefix   = local.app
  region        = local.region
  name_override = "${local.app}-lab"
}

# Log Analytics
module "log-analytics-workspace-lab" {
  source              = "./modules/log-analytics-workspace"
  name                = "${local.app}-lab-log-analytics"
  region              = local.region
  resource_group_name = module.rg-lab.rg_name
}

# Kusto
module "kusto-lab" {
  source = "./modules/kusto"

  // Different naming convention as 22-char max length
  cluster_name                 = "ghaumlab"
  environment                  = "lab"
  region                       = local.region
  resource_group_name          = module.rg-lab.rg_name
  reader_spn                   = toset([local.runtime_service_principal_id_lab, local.ci_service_principal_id])
  sku_name                     = local.kusto_cluster_sku_name
  auto_scale_minimum_instances = 8
  auto_scale_maximum_instances = 20
  app                          = local.app
  log_analytics_workspace_id   = module.log-analytics-workspace-lab.log_analytics_workspace_id
  jit_group_id                 = local.jit_group_id
}

# Storage Account
module "storage-account-lab" {
  source = "./modules/storage-account"

  account_name               = "actionsmetricslab"
  region                     = local.region
  resource_group_name        = module.rg-lab.rg_name
  app                        = local.app
  environment                = "lab"
  log_analytics_workspace_id = module.log-analytics-workspace-lab.log_analytics_workspace_id
}

module "additional-stamps" {
  for_each = { for stamp in local.stamps : stamp.stamp => stamp }
  source   = "./modules/stamp"

  stamp  = each.key
  spn_id = each.value.spn_id
  region = each.value.region

  app                    = local.app
  jit_group_id           = local.jit_group_id
  kusto_cluster_sku_name = local.kusto_cluster_sku_name

}
