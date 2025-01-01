# typed: true
# frozen_string_literal: true

class GlobalNoticeNext
  class ScheduledBaseCheck < BaseCheck
    def is_scheduled?
      true
    end

    def self.find_eligible(user_ids)
      raise "Please implement #find_eligible"
    end
  end
end
