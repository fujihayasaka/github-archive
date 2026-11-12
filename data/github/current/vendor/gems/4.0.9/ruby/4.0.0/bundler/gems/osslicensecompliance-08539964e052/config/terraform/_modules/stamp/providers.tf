terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "3.40.0"
    }
    octovault = {
      source  = "terraform.githubapp.com/shared-providers/octovault"
      version = ">= 2.0.0"
    }
  }
}

provider "azurerm" {
  subscription_id            = "d206e280-49d9-4a86-b28c-54734f42ca2c"
  storage_use_azuread        = true
  skip_provider_registration = true
  use_oidc                   = true
  features {}
}
