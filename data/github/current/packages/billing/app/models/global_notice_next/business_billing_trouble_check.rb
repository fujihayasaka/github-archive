# typed: strict
# frozen_string_literal: true

class GlobalNoticeNext
  class BusinessBillingTroubleCheck < BaseCheck
    extend T::Sig

    sig { override.returns(T::Boolean) }
    def should_show_notice?
      return false unless viewer.business_billing_trouble?
      @troubled_business = T.let(viewer.billing_troubled_businesses.first, T.nilable(::Business))
      true
    end
  end
end
