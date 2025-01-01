# typed: strict
# frozen_string_literal: true

module SecretScanning
  module ExemptionConstants
    # The value for the 'request_type' field in Exemptions::ExemptionRequest
    EXEMPTION_REQUEST_TYPE = "secret_scanning"

    # The value for the 'request_type' field in Exemptions::ExemptionRequest, for secret scanning alert closure requests
    CLOSURE_EXEMPTION_REQUEST_TYPE = "secret_scanning_closure"

    # The reasons for which a user can request to dismiss a secret scanning alert
    VALID_REASONS = T.let(Set.new(%w[
      false_positive
      revoked
      used_in_tests
      wont_fix
    ]), T::Set[String])

    CLOSE_REASON_NAMES = T.let(
    {
      "false_positive": "False positive",
      "used_in_tests": "Used in tests",
      "wont_fix": "Won't fix",
      "revoked": "Revoked"
    }, T::Hash[Symbol, String])

    # The details for each reason for which a user can request to dismiss a secret scanning alert.
    # Used in emails.
    CLOSE_REASON_DETAILS = T.let(
      {
        "wont_fix": "This alert is not relevant",
        "false_positive": "This alert is not valid",
        "used_in_tests": "This alert is not in production code",
        "revoked": "This alert has been revoked"
      }, T::Hash[String, String])
  end
end
