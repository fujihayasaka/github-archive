locals {
  environment = "prod-ae-01"
  stamp_name  = "prod_ae_01"
}

module "application" {
  source = "../application"

  providers = {
    azurerm   = azurerm
    octovault = octovault
  }

  vault_environment          = local.environment
  rg_name_override           = "data"
  create_rg                  = false // Because this shares an RG with Production, and shouldn't be "managed" by the TF for this stamp
  stamp_name                 = local.stamp_name
  automatic_failover_enabled = true
  cosmos_account_name        = "gh-billing-platform-prod-ae-01"
  additional_tags = {
    "defaultExperience"       = "Core (SQL)"
    "hidden-cosmos-mmspecial" = ""
  }
  storage_account_rg_name = "metered_billing_prodae01"
  storage_account_name    = "mbprodae01"

  additional_ips = []
}
