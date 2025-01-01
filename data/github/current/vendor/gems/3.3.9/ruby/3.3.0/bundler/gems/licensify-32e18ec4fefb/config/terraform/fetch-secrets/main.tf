/*
Local module used to encapsulate which secrets are required to during a deployment of a
root module and how those secrets are fetched.

Refer to following documentation for a reminder about the self-service service principal (SPN) generation process:
https://github.com/github/security-iam/blob/b848744e5088ac5010868c4a2b382b49482c3a26/docs/how_to_azure_serviceprincipal.md
*/
data "octovault_application_secret" "service_principal_client_secret" {
  application = var.vault_application
  environment = var.vault_environment
  key         = "spn_${var.catalog_service_name}_tf"
}

data "octovault_application_secret" "service_principal_client_id" {
  application = var.vault_application
  environment = var.vault_environment
  key         = "spn_${var.catalog_service_name}_tf_client_id"
}

data "octovault_application_secret" "service_principal_tenant_id" {
  application = var.vault_application
  environment = var.vault_environment
  key         = "spn_${var.catalog_service_name}_tf_tenant_id"
}

output "service_principal_client_secret" {
  value     = data.octovault_application_secret.service_principal_client_secret.value
  sensitive = true
}

output "service_principal_client_id" {
  value     = data.octovault_application_secret.service_principal_client_id.value
  sensitive = true
}

output "service_principal_tenant_id" {
  value     = data.octovault_application_secret.service_principal_tenant_id.value
  sensitive = true
}
