# typed: true
# frozen_string_literal: true

module Billing
  class ExpiredEducationCouponCheckJob < BillingJob
    discard_on ActiveJob::DeserializationError

    def perform(account)
      return unless account.has_expired_education_coupon?

      if account.organization?
        account.admins.each do |admin|
          global_notice = GlobalNoticeNext.new(viewer: admin)
          with_write { global_notice.set_notice(:expired_education_coupon) }
        end
      else
        global_notice = GlobalNoticeNext.new(viewer: account)
        with_write { global_notice.set_notice(:expired_education_coupon) }
      end
    end
  end
end
