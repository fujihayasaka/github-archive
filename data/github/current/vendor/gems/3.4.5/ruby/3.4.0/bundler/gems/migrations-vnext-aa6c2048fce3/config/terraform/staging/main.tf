terraform {
  backend "remote" {
    hostname     = "terraform.githubapp.com"
    organization = "azure-migrations-vnext"
    workspaces {
      name = "staging"
    }
  }
}

provider "azurerm" {
  storage_use_azuread = true
  features {}
  subscription_id            = "f7c0eeab-405c-4d5f-a862-e68b53b77d1a"
  client_secret              = data.octovault_application_secret.service_principal_client_secret.value
  tenant_id                  = data.octovault_application_secret.service_principal_tenant_id.value
  client_id                  = data.octovault_application_secret.service_principal_client_id.value
  skip_provider_registration = true
}

provider "octovault" {}

data "octovault_application_secret" "service_principal_client_secret" {
  application = var.vaultapp
  environment = var.vaultenv
  key         = "spn_migrations_vnext_${var.rgenv}_tf"
}

data "octovault_application_secret" "service_principal_client_id" {
  application = var.vaultapp
  environment = var.vaultenv
  key         = "spn_migrations_vnext_${var.rgenv}_tf_client_id"
}

data "octovault_application_secret" "service_principal_tenant_id" {
  application = var.vaultapp
  environment = var.vaultenv
  key         = "spn_migrations_vnext_${var.rgenv}_tf_tenant_id"
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "rg" {
  location = var.region
  name     = "migrations_vnext_terraform_${var.rgenv}"
  tags     = var.tags
}