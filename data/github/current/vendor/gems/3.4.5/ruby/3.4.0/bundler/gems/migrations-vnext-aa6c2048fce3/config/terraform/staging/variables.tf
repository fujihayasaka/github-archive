variable "rgenv" {
  type    = string
  default = "staging"
}

variable "env" {
  type    = string
  default = "staging"
}

variable "vaultapp" {
  type    = string
  default = "migrations-vnext"
}

variable "vaultenv" {
  type    = string
  default = "staging"
}

variable "region" {
  type    = string
  default = "eastus"
}

variable "tags" {
  type = map(string)
  default = {
    environment     = "staging"
    catalog_service = "github/migrations-vnext"
  }
}
