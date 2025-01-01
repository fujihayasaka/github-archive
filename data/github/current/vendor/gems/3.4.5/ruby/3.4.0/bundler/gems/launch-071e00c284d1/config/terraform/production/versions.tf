terraform {
  required_version = ">= 1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.5"
    }
    octovault = {
      source = "terraform.githubapp.com/shared-providers/octovault"
      version = ">= 1.0.7"
    }
  }
}