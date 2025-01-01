# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "github/transitions/move_key_values_base"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class MoveAuthenticationKeyValues < MoveKeyValuesBase
      class AuthenticationKeyValues < ApplicationRecord::Domain::Authentication
        self.table_name = :authentication_key_values
      end

      sig { override.returns(T.class_of(ApplicationRecord::Base)) }
      def model_class
        AuthenticationKeyValues
      end

      iterate_key_values [
        "AddTwoFactorSMSBackupOTP:%",
        "qintel:%",
        "TwoFactorRequirementDiscoveryJob.%",
        "v3:auth_failure:%",
        "totp::last_otp_at::%",
        "rate_limit:auth_limit_by_%",
        "two-factor-recovery-request-review-%",
        "two_factor_authentication_setup:%",
        "bypass-account-2fa-requirement-interrupt:%",
        "user.security_checkup_completed_at.%",
        "security-checkup-updated:%",
        "security-checkup-force:%",
        "user.two_factor_checkup_due_at.%",
        "user.two_factor_checkup_delay_count.%",
        "user.two_factor_holiday_warning_dismissed.%",
        "TwoFactorSMSFallbackProvider:%",
        "%:two_factor_locked",
        "%pat_org_request_email%",
        "%pat_expired_email%",
        "%pat_expiry_email%",
        "%compromised_password_check%",
        "%compromised_password_notification%",
        "%analyze_failed_sign_in%",
        "%programmatic_access_email_notification%",
      ]
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  # See the transition arguments class for information about standard
  # arguments and their default values. If you require additional arguments,
  # pass them via `additional_arguments: %w(foo)` to the `parse` method.
  args = GitHub::Transitions::Arguments.parse(ARGV, additional_arguments: %w(cleanup))

  GitHub::Transitions::MoveAuthenticationKeyValues.new(args).run
end
