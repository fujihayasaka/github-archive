# typed: strict
# frozen_string_literal: true

class GlobalNoticeNext
  class BusinessUpcomingRenewalCheck < BaseCheck

    sig { override.returns(T::Boolean) }
    def should_show_notice?
      viewer&.renewal_eligible_business.present?
    end
  end
end
