# typed: true
# frozen_string_literal: true

module Billing
  class BillingEmailCheckJob < BillingJob
    queue_as :billing

    discard_on ActiveJob::DeserializationError

    def perform(account)
      return unless account.billing_email_invalid?

      if account.organization?
        account.admins.each do |admin|
          global_notice = GlobalNoticeNext.new(viewer: admin)
          with_write { global_notice.set_notice(:billing_email) }
        end
      else
        notice = GlobalNoticeNext.new(viewer: account)
        with_write { notice.set_notice(:billing_email) }
      end
    end
  end
end
