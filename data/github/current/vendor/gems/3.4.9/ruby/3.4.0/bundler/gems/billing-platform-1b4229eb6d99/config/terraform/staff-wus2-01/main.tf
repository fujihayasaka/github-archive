locals {
  environment = "staff-wus2-01"
  stamp_name  = "staff_wus2_01"
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
  cosmos_account_name        = "gh-billing-platform-staff-wus2-01"
  additional_tags = {
    "defaultExperience"       = "Core (SQL)"
    "hidden-cosmos-mmspecial" = ""
  }
  storage_account_rg_name = "metered_billing_staffwus201"
  storage_account_name    = "mbstaffwus201"

  additional_ips = [
    "68.83.241.204",
    "142.115.82.206",
    "98.216.144.88",
    "73.33.132.111",
    "108.54.252.129",
    "207.229.149.53",
    "73.53.109.200",
  ]
}
