data "octovault_application_secret" "aqueduct_api_key" {
  application = "aqueduct-client-turboghas"
  environment = "${var.stamp_name}"
  key = "AQUEDUCT_API_KEY_TURBOGHAS_V${var.stamp_aqueduct_api_key_version}"
}

resource "octovault_application_secret" "aqueduct_api_key_version" {
  application = "turboghas"
  environment = "${var.stamp_name}"

  key = "AQUEDUCT_API_KEY_VERSION"
  value = "${var.stamp_aqueduct_api_key_version}"
}

resource "octovault_application_secret" "aqueduct_api_key" {
  application = "turboghas"
  environment = "${var.stamp_name}"

  key = "AQUEDUCT_API_KEY"
  value = "${data.octovault_application_secret.aqueduct_api_key.value}"
}
