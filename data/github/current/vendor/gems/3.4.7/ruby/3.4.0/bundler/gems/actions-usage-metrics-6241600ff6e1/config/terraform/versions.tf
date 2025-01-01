terraform {
  required_version = ">= 1.0, < 1.4.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.94.0"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "3.20.1"
    }
    octovault = {
      source  = "terraform.githubapp.com/shared-providers/octovault"
      version = ">= 1.0.11"
    }
  }
}
