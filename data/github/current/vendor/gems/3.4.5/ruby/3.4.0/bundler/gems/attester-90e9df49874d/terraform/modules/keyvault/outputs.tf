output "octovault_client_id" {
  value = data.octovault_application_secret.client_id.value
}

output "octovault_tenant_id" {
  value = data.octovault_application_secret.tenant_id.value
}

output "octovault_client_secret" {
  value     = data.octovault_application_secret.client_secret.value
  sensitive = true
}
