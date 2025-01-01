# typed: strict
# frozen_string_literal: true

class GlobalNoticeNext
  class BillingEmailCheck < BaseCheck

    sig { override.returns(T::Boolean) }
    def should_show_notice?
      return false unless viewer.billing_email_invalid?
      true
    end
  end
end
