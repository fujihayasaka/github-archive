variable "rgenv" {
  type    = string
  default = "prod_weu_01"
}

variable "env" {
  type    = string
  default = "prodweu01"
}

variable "vaultapp" {
  type    = string
  default = "migrations-vnext"
}

variable "vaultenv" {
  type    = string
  default = "prod-weu-01"
}

variable "region" {
  type    = string
  default = "westeurope"
}

variable "tags" {
  type = map(string)
  default = {
    environment     = "prod-weu-01"
    catalog_service = "github/migrations-vnext"
  }
}