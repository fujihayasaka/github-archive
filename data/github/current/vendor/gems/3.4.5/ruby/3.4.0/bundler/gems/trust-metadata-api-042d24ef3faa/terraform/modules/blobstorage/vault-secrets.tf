data "octovault_application_secret" "tenant_id" {
  application = "trust-metadata-api"
  environment = var.env
  key         = var.azure_tenant_id
}

data "octovault_application_secret" "client_id" {
  application = "trust-metadata-api"
  environment = var.env
  key         = var.azure_client_id
}

data "octovault_application_secret" "client_secret" {
  application = "trust-metadata-api"
  environment = var.env
  key         = var.azure_client_secret
}
