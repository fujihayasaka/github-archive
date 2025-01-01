# typed: true
# frozen_string_literal: true

module Billing
  class OFACCompliance
    USER_NOTICE_FLAG = :check_ofac_flagged
    TRADE_CONTROLS_READ_ONLY = :trade_controls_read_only
    FREE_ORG_NOTICE_FLAG = :free_org_ofac_flagged
  end
end
