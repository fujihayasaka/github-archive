# typed: true
# frozen_string_literal: true

class GlobalNoticeNext
  class TwoFactorLowRecoveryCodesCheck < BaseCheck
    def should_show_notice?
      return false unless viewer.two_factor_authentication_enabled?
      viewer.two_factor_credential.number_of_remaining_codes < 5
    end
  end
end
