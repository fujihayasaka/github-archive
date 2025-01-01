# Access Azure Service Principal credentials from Vault
data "octovault_application_secret" "tenant_id" {
  application = "osslicensecompliance"
  environment = "terraform"
  key         = "spn_osslicensecompliance_tf_tenant_id"
}
output "tenant_id" {
  value = data.octovault_application_secret.tenant_id.value
}

data "octovault_application_secret" "client_id" {
  application = "osslicensecompliance"
  environment = "terraform"
  key         = "spn_osslicensecompliance_tf_client_id"
}
output "client_id" {
  value = data.octovault_application_secret.client_id.value
}

data "octovault_application_secret" "client_secret" {
  application = "osslicensecompliance"
  environment = "terraform"
  key         = "spn_osslicensecompliance_tf"
}
output "client_secret" {
  value = data.octovault_application_secret.client_secret.value
}
