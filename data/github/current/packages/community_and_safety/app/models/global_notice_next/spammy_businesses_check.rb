# typed: true
# frozen_string_literal: true

class GlobalNoticeNext
  class SpammyBusinessesCheck < BaseCheck
    def type
      "error"
    end

    def should_show_notice?
      spammy_business = viewer.businesses(membership_type: :admin).any? do |business|
        business.spammy?
      end

      spammy_business.present?
    end
  end
end
