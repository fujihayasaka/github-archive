variable "rgenv" {
  type    = string
  default = "staff_wus2_01"
}

variable "env" {
  type    = string
  default = "staffwus201"
}

variable "vaultapp" {
  type    = string
  default = "migrations-vnext"
}

variable "vaultenv" {
  type    = string
  default = "staff-wus2-01"
}

variable "region" {
  type    = string
  default = "westus2"
}

variable "tags" {
  type = map(string)
  default = {
    environment     = "staff-wus2-01"
    catalog_service = "github/migrations-vnext"
  }
}