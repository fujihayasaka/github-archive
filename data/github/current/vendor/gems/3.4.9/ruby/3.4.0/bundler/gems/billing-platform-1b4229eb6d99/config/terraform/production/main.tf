locals {
  environment              = "production"
  stamp_name               = "dotcom"
  data_resource_group_name = "data"
}

module "application" {
  source = "../application"

  providers = {
    azurerm   = azurerm
    octovault = octovault
  }

  vault_environment          = local.environment
  rg_name_override           = local.data_resource_group_name
  stamp_name                 = local.stamp_name
  allow_gh_dcs               = false // use this in the future and remove the GitHub DC IPs from additional IPs
  automatic_failover_enabled = false
  cosmos_account_name        = "billing-platform"
  additional_tags = {
    "defaultExperience"       = "Core (SQL)"
    "hidden-cosmos-mmspecial" = ""
  }
  database_autoscale_max_throughput = 16699000
  storage_account_rg_name = "metered_billing_${local.environment}"
  storage_account_name    = "mbproduction"

  additional_ips = [
    "192.30.252.0/22", // remove once allow_gh_dcs is set to true
    "185.199.108.0/22",// remove once allow_gh_dcs is set to true
    "140.82.112.0/20", // remove once allow_gh_dcs is set to true
    "143.55.64.0/20", // remove once allow_gh_dcs is set to true
    "71.234.86.246",
    "198.72.184.234",
    "76.121.86.13",
    "100.0.241.53",
    "68.83.241.204",
    "136.58.9.200",
    "80.136.81.183",
    "142.115.82.206",
    "20.169.173.186",
    "207.229.149.53",
    "72.74.49.234",
    "73.33.132.111", //@sridharavinash
    "189.122.235.125",
    "136.56.41.127",
    "75.157.69.141",
    "108.54.252.129",
    "98.216.144.88",
    "75.49.171.105",
    "99.247.233.84"
  ]
}
