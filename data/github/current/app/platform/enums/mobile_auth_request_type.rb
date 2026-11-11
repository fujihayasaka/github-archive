# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class MobileAuthRequestType < Platform::Enums::Base
      required_capabilities [:mobile_only_schema_mask]
      description "Represents the different mobile auth request types."

      value "UNKNOWN", "The request came from an unknown flow.", value: "unknown"
      value "TWO_FACTOR_LOGIN", "The request came from the two factor login flow.", value: "2fa_login"
      value "DEVICE_VERIFICATION", "The request came from the device verification flow.", value: "device_verification"
      value "TWO_FACTOR_PASSWORD_RESET", "The request came from the two factor password reset flow.", value: "2fa_password_reset"
      value "TWO_FACTOR_SUDO_CHALLENGE", "The request came from the Sudo challenge.", value: "2fa_sudo_challenge"
    end
  end
end
