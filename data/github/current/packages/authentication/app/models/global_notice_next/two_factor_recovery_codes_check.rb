# typed: true
# frozen_string_literal: true

class GlobalNoticeNext
  class TwoFactorRecoveryCodesCheck < BaseCheck
    def should_show_notice?
      viewer.two_factor_authentication_enabled? &&
        !viewer.two_factor_credential.recovery_codes_viewed?
    end
  end
end
