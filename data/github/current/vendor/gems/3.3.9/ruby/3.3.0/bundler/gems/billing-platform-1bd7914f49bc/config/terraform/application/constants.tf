locals {
  team_prefix = "billing-platform"
  vault_application = "billing-platform"
}

variable "primary_regions" {
  type = map(object({
    location       = string,
    zone_redundant = bool
  }))
  default = {
    prod_ae_01 = {
      location = "australiaeast"
      zone_redundant = false
    }
    dotcom = {
      location = "eastus"
      zone_redundant = false
    }
    staff_wus2_01 = {
      location = "westus2"
      zone_redundant = false
    }
    prod_weu_01 = {
      location = "westeurope"
      zone_redundant = false
    }
    prod_sdc_01 = {
      location = "swedencentral"
      zone_redundant = false
    }
  }
}

variable "secondary_regions" {
  type = map(list(object({
    location          = string,
    failover_priority = number,
    zone_redundant    = bool
  })))
  default = {
    prod_ae_01 = [{
      failover_priority = 1
      location = "australiasoutheast"
      zone_redundant = false
    }]
    // TODO: consider secondary region for dotcom
    dotcom = []
    staff_wus2_01 = [{
      failover_priority = 1
      location          = "westus"
      zone_redundant    = false
    }]
    prod_weu_01 = [{
      failover_priority = 1
      location          = "northeurope"
      zone_redundant    = false
    }]
    prod_sdc_01 = [{
      failover_priority = 1
      location          = "swedensouth"
      zone_redundant    = false
    }]
  }
}
