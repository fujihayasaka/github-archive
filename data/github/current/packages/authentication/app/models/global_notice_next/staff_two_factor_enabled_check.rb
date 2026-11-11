# typed: true
# frozen_string_literal: true

class GlobalNoticeNext
  class StaffTwoFactorEnabledCheck < BaseCheck
    def should_show_notice?
      viewer.site_admin_without_two_factor_check? && !viewer.site_admin?
    end
  end
end
