data "octovault_application_secret" "aqueduct_api_key" {
  application = "aqueduct-client-turboscan"
  environment = "${var.stamp_name}"
  key = "AQUEDUCT_API_KEY_TURBOSCAN_V${var.stamp_aqueduct_api_key_version}"
}

resource "octovault_application_secret" "aqueduct_api_key" {
  application = "turboscan"
  environment = "${var.stamp_name}"

  key = "AQUEDUCT_API_KEY"
  value = "${data.octovault_application_secret.aqueduct_api_key.value}"
}
