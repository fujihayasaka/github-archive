# Declare the usage of Azure Provider
terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

# Reference: https://www.terraform.io/docs/providers/azurerm/index.html
provider "azurerm" {
  storage_use_azuread = true
  features {}
}

# Allows access to useful Azure Tenant information in context
# Reference: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/client_config
data "azurerm_client_config" "current" {}
