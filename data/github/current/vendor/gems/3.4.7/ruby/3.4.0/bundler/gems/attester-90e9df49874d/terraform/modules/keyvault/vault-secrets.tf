data "octovault_application_secret" "tenant_id" {
  application = "attester"
  environment = var.vault_env
  key         = var.azure_tenant_id
}

data "octovault_application_secret" "client_id" {
  application = "attester"
  environment = var.vault_env
  key         = var.azure_client_id
}

data "octovault_application_secret" "client_secret" {
  application = "attester"
  environment = var.vault_env
  key         = var.azure_client_secret
}
