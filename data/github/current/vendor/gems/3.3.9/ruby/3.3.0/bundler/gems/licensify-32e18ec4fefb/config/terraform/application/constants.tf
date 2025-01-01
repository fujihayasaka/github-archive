variable "primary_regions" {
  type = map(object({
    location      = string,
    zone_redundant = bool
  }))
  default = {
    dotcom = {
      location       = "eastus",
      zone_redundant = false
    }
    staff-wus2-01 = {
      location       = "westus2",
      zone_redundant = false
    }
    prod-weu-01 = {
      location       = "westeurope",
      zone_redundant = false
    }
    prod-sdc-01 = {
      location       = "swedencentral",
      zone_redundant = false
    }
    prod-ae-01 = {
      location       = "australiaeast",
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
    dotcom = [{
      failover_priority = 1
      location          = "westus"
      zone_redundant    = false
    }]
    staff-wus2-01 = [{
      failover_priority = 1
      location          = "centralus"
      zone_redundant    = false
    }]
    prod-weu-01 = [{
      failover_priority = 1
      location          = "northeurope"
      zone_redundant    = false
    }]
    prod-sdc-01 = [{
      failover_priority = 1
      location          = "swedensouth"
      zone_redundant    = false
    }]
    prod-ae-01 = [{
      failover_priority = 1
      location          = "australiasoutheast"
      zone_redundant    = false
    }]
  }
}
