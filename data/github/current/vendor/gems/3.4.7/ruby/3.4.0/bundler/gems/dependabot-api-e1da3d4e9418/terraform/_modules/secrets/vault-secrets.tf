data "octovault_application_secret" "tenant_id" {
  application = "dependabot-api"
  environment = "production"
  key = "spn_dependabot_api_tf_tenant_id"
}
output "tenant_id" {
  value = data.octovault_application_secret.tenant_id.value
}

data "octovault_application_secret" "client_id" {
  application = "dependabot-api"
  environment = "production"
  key = "spn_dependabot_api_tf_client_id"
}
output "client_id" {
  value = data.octovault_application_secret.client_id.value
}

data "octovault_application_secret" "client_secret" {
  application = "dependabot-api"
  environment = "production"
  key = "spn_dependabot_api_tf"
}
output "client_secret" {
  value = data.octovault_application_secret.client_secret.value
}
