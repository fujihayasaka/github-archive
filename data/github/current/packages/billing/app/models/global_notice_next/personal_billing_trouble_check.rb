# typed: strict
# frozen_string_literal: true

class GlobalNoticeNext
  class PersonalBillingTroubleCheck < BaseCheck

    sig { override.returns(T::Boolean) }
    def should_show_notice?
      viewer.billing_trouble?
    end
  end
end
