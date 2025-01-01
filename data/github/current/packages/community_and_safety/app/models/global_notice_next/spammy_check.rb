# typed: true
# frozen_string_literal: true

class GlobalNoticeNext
  class SpammyCheck < BaseCheck
    def type
      "error"
    end

    def should_show_notice?
      viewer.spammy?
    end
  end
end
