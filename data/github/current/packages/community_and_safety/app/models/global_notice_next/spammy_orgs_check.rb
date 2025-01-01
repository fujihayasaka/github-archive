# typed: true
# frozen_string_literal: true

class GlobalNoticeNext
  class SpammyOrgsCheck < BaseCheck
    def type
      "error"
    end

    def should_show_notice?
      spammy_org = viewer.owned_organizations.any? do |org|
        org.spammy?
      end

      spammy_org.present?
    end
  end
end
