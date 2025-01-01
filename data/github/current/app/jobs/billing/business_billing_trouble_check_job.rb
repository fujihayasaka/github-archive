# typed: true
# frozen_string_literal: true

module Billing
  class BusinessBillingTroubleCheckJob < BillingJob
    queue_as :billing

    discard_on ActiveJob::DeserializationError

    def perform(account)
      return unless account.billing_trouble?

      account.owners.each do |owner|
        global_notice = GlobalNoticeNext.new(viewer: owner)
        with_write { global_notice.set_notice(:business_billing_trouble) }
      end
    end
  end
end
