terraform {
  required_providers {
    octovault = {
      source  = "terraform.githubapp.com/shared-providers/octovault"
      version = "~> 2.0.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.92.0"
    }
  }
}
