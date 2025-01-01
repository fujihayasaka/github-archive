# typed: true
# frozen_string_literal: true

class GlobalNoticeNext
  class ExpiredEducationCouponCheck < BaseCheck
    extend T::Sig

    sig { override.returns(T::Boolean) }
    def should_show_notice?
      !!viewer.has_expired_education_coupon?
    end
  end
end
