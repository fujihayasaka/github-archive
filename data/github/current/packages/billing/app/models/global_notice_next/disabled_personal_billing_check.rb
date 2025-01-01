# typed: strict
# frozen_string_literal: true

class GlobalNoticeNext
  class DisabledPersonalBillingCheck < BaseCheck
    extend T::Sig

    sig { override.returns(String) }
    def type
      "error"
    end

    sig { override.returns(T::Boolean) }
    def should_show_notice?
      viewer.disabled? && viewer.paid_plan?
    end
  end
end
