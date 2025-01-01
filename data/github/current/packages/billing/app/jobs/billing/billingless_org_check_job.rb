# typed: true
# frozen_string_literal: true

module Billing
  class BillinglessOrgCheckJob < BillingJob
    discard_on ActiveJob::DeserializationError

    def perform(account)
      return unless account.organization? && account.billing_email.blank? && account.paid_plan?

      account.admins.each do |admin|
        global_notice = GlobalNoticeNext.new(viewer: admin)
        with_write { global_notice.set_notice(:billingless_org) }
      end
    end
  end
end
