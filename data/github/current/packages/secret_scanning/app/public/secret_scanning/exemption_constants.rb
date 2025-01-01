# typed: strict
# frozen_string_literal: true

module SecretScanning
  module ExemptionConstants
    # The value for the 'request_type' field in Exemptions::ExemptionRequest, for secret scanning alert closure requests
    CLOSURE_EXEMPTION_REQUEST_TYPE = "secret_scanning_closure"
  end
end
