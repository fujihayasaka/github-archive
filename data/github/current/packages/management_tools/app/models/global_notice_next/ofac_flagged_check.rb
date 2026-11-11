# typed: true
# frozen_string_literal: true

class GlobalNoticeNext
  class OFACFlaggedCheck < BaseCheck
    def should_show_notice?
      viewer.has_any_trade_restrictions? && !viewer.dismissed_notice?(Billing::OFACCompliance::USER_NOTICE_FLAG)
    end
  end
end
