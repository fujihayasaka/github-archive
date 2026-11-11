terraform {
  required_version = ">= 0.14.6"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.47.0"
    }
    octovault = {
      source = "terraform.githubapp.com/shared-providers/octovault"
      version = ">= 2.3.1"
    }
  }
  backend "remote" {
    hostname     = "terraform.githubapp.com"
    organization = "azure-security-dependabot-updates-prod"
    workspaces {
      name = "dependabot-api-test-cnc-01"
    }
  }
}

module "secrets" {
  source = "../_modules/secrets"
}

module "subscription" {
  source = "../_modules/common"
}

provider "azurerm" {
  resource_provider_registrations = "extended"
  features {}
  tenant_id = module.secrets.tenant_id
  client_id = module.secrets.client_id
  client_secret = module.secrets.client_secret
  subscription_id = module.subscription.subscription_id
}

module "stamp" {
  source = "../_modules/stamp"
  stamp_name = "test-cnc-01"
  stamp_azure_region = "canadacentral"
}
