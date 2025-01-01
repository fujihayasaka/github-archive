# typed: true
# frozen_string_literal: true

class GlobalNoticeNext
  class SponsorshipRollbackCheck < BaseCheck
    def should_show_notice?
      !viewer.dismissed_notice?(:sponsorship_rollback) && viewer.has_sponsorship_rollback?
    end
  end
end
