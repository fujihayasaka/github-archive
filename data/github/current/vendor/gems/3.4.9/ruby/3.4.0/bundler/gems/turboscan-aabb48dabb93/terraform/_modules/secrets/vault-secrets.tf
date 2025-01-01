data "octovault_application_secret" "tenant_id" {
  application = "turboscan"
  environment = "terraform"
  key = "spn_github_code_scanning_tf_tenant_id"
}
output "tenant_id" {
  value = data.octovault_application_secret.tenant_id.value
}

data "octovault_application_secret" "client_id" {
  application = "turboscan"
  environment = "terraform"
  key = "spn_github_code_scanning_tf_client_id"
}
output "client_id" {
  value = data.octovault_application_secret.client_id.value
}

data "octovault_application_secret" "client_secret" {
  application = "turboscan"
  environment = "terraform"
  key = "spn_github_code_scanning_tf"
}
output "client_secret" {
  value = data.octovault_application_secret.client_secret.value
}
