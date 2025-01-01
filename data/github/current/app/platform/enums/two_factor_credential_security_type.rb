# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class TwoFactorCredentialSecurityType < Platform::Enums::Base
      description "Filters by whether or not 2FA is enabled and if the method configured is considered secure or insecure."

      value "SECURE", "Has only secure methods of two-factor authentication.", value: "secure"
      value "INSECURE", "Has an insecure method of two-factor authentication. GitHub currently defines this as SMS two-factor authentication.", value: "insecure"
      value "DISABLED", "No method of two-factor authentication.", value: "disabled"
    end
  end
end
