terraform {
  cloud {
    hostname = "terraform.githubapp.com"
    organization = "azure-billing-prod"

    workspaces {
      name = "billing-platform-prod-cus-01"
    }
  }
}

provider "azurerm" {
  storage_use_azuread = true
  features {}
  subscription_id = "04b4bc34-e931-4274-82d6-f5b61c8fc48e"
}
