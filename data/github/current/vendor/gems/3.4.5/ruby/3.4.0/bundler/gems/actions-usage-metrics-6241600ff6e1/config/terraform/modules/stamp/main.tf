locals {
  safe_name = replace(var.stamp, "-", "")
}

module "rg-stamp" {
  source  = "terraform.githubapp.com/azure-data-patterns-and-scaling/github-cosmos/azurerm//modules/azure-resource-group"
  version = "0.1.2" # Be sure to use the latest version you can

  team_prefix   = var.app
  region        = var.region
  name_override = "${var.app}-${var.stamp}"
}

# Log Analytics
module "log-analytics-workspace-stamp" {
  source              = "../log-analytics-workspace"
  name                = "${var.app}-${var.stamp}-log-analytics"
  region              = var.region
  resource_group_name = module.rg-stamp.rg_name
}

# Kusto
module "kusto-stamp" {
  source = "../kusto"

  // Different naming convention as 22-char max length
  cluster_name                 = "ghaum${local.safe_name}"
  environment                  = var.stamp
  region                       = var.region
  resource_group_name          = module.rg-stamp.rg_name
  reader_spn                   = toset([var.spn_id])
  sku_name                     = var.kusto_cluster_sku_name
  auto_scale_minimum_instances = 8
  auto_scale_maximum_instances = 20
  app                          = var.app
  log_analytics_workspace_id   = module.log-analytics-workspace-stamp.log_analytics_workspace_id
  jit_group_id                 = var.jit_group_id
}

# Storage Account
module "storage-account-stamp" {
  source = "../storage-account"

  account_name               = "aum${local.safe_name}" // hyphens not allowed and must be under 24 chars (hence naming change from prod and lab)
  region                     = var.region
  resource_group_name        = module.rg-stamp.rg_name
  app                        = var.app
  environment                = var.stamp
  log_analytics_workspace_id = module.log-analytics-workspace-stamp.log_analytics_workspace_id
}
