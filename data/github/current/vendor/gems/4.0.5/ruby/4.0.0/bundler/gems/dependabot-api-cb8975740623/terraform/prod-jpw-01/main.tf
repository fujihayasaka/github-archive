terraform {
  required_version = ">= 0.14.6"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.66.0"
    }
  }
  backend "remote" {
    hostname     = "terraform.githubapp.com"
    organization = "azure-security-dependabot-updates-prod"
    workspaces {
      name = "dependabot-api-prod-jpw-01"
    }
  }
}

module "subscription" {
  source = "../_modules/common"
}

provider "azurerm" {
  resource_provider_registrations = "extended"
  features {}
  subscription_id = module.subscription.subscription_id
  use_oidc        = true
}

module "stamp" {
  source = "../_modules/stamp"
  stamp_name = "prod-jpw-01"
  stamp_azure_region = "japanwest"
}
