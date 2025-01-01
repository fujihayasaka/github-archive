# typed: strict
# frozen_string_literal: true

class GlobalNoticeNext
  class BillinglessOrgCheck < BaseCheck
    extend T::Sig

    sig { override.returns(String) }
    def type
      "error"
    end

    sig { override.returns(T::Boolean) }
    def should_show_notice?
      viewer.owns_billingless_org?
    end
  end
end
