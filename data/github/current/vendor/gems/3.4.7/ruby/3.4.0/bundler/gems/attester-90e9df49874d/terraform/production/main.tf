terraform {
  backend "remote" {
    hostname     = "terraform.githubapp.com"
    organization = "package-security"
    workspaces {
      name = "attester-production"
    }
  }
}

module "keyvault" {
  source = "../modules/keyvault"

  # env is used for naming resources
  env = var.env
  # vault_env is used to choose a Vault environment, it must be lowercase
  vault_env           = var.vault_env
  azure_tenant_id     = var.azure_tenant_id
  azure_client_id     = var.azure_client_id
  azure_client_secret = var.azure_client_secret
  subscription_id     = var.subscription_id
  # PagerDuty webhook integration URL, used to send Azure alerts to PagerDuty
  pagerduty_integration_url     = var.pagerduty_integration_url
  public_network_access_enabled = var.public_network_access_enabled
  default_action                = var.default_action
  allow_gh_dcs                  = var.allow_gh_dcs
  additional_ips_to_allow       = var.additional_firewall_ips
}

provider "azurerm" {
  features {}
  tenant_id       = module.keyvault.octovault_tenant_id
  client_id       = module.keyvault.octovault_client_id
  client_secret   = module.keyvault.octovault_client_secret
  subscription_id = var.subscription_id
}
