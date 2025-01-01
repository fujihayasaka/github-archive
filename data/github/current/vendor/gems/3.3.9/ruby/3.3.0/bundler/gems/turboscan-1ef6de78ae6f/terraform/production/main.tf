terraform {
  required_version = ">= 0.14.6"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 2.95.0"
    }
    octovault = {
      source = "terraform.githubapp.com/shared-providers/octovault"
      version = ">= 2.0.0"
    }
  }
  backend "remote" {
    hostname     = "terraform.githubapp.com"
    organization = "azure-dsp-code-scanning-experiences-prod"
    workspaces {
      name = "turboscan-production"
    }
  }
}

module "secrets" {
  source = "../_modules/secrets"
}

provider "azurerm" {
  features {}
  tenant_id = module.secrets.tenant_id
  client_id = module.secrets.client_id
  client_secret = module.secrets.client_secret
  subscription_id = "02688c9a-46f1-471a-99cf-545c30f7235d"
}

module "stamp" {
  source = "../_modules/stamp"
  stamp_name = "production"
  stamp_azure_name = "prod"
  stamp_azure_region = "eastus"
  stamp_elasticsearch_cluster_name = "shared_search_es8"
  stamp_elasticsearch_username = "turboscan_1"
  stamp_mysql_credential_prefix = "TURBOSCAN_"
}
