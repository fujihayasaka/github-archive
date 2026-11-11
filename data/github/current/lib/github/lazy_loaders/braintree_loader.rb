# typed: strict
# frozen_string_literal: true

require "braintree"

if GitHub.billing_enabled?
  ::Braintree::Configuration.environment = GitHub.braintree_environment
  ::Braintree::Configuration.merchant_id = GitHub.braintree_merchant_id
  ::Braintree::Configuration.public_key  = GitHub.braintree_public_key
  ::Braintree::Configuration.private_key = GitHub.braintree_private_key
  # To adjust the verbosity of the Braintree logs, set the GITHUB_TELEMETRY_LOGS_LIB_LEVEL env var.
  ::Braintree::Configuration.logger = ::GitHub::Telemetry::Logs.lib_logger("Braintree")
end

# Prefer "Türkiye" rather than "Turkey"
if tr_index = Braintree::Address::CountryNames.find_index { |c| c[1] == "TR" }
  Braintree::Address::CountryNames[tr_index][0] = "Türkiye"
end
