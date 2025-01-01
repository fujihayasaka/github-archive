terraform {
  required_version = ">= 1.0, < 1.4.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    octovault = {
      source  = "terraform.githubapp.com/shared-providers/octovault"
      version = ">= 1.0.7"
    }
  }
}
