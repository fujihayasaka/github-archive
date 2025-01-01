locals {
  environment = "prod-weu-01"
  stamp_name  = "prod_weu_01"
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
  cosmos_account_name        = "gh-billing-platform-prod-weu-01"
  additional_tags = {
    "defaultExperience"       = "Core (SQL)"
    "hidden-cosmos-mmspecial" = ""
  }
  storage_account_rg_name = "metered_billing_prodweu01"
  storage_account_name    = "mbprodweu01"

  additional_ips = [
    "68.83.241.204",
    "142.115.82.206",
    "108.54.252.129",
    "207.229.149.53",
    "98.216.144.88",
    "73.53.109.200"
  ]
}
