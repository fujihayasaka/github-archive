# typed: true
# frozen_string_literal: true

module Billing
  class PersonalBillingTroubleCheckJob < BillingJob
    queue_as :billing

    discard_on ActiveJob::DeserializationError

    def perform(account)
      return unless account.user? && account.billing_trouble?

      global_notice = GlobalNoticeNext.new(viewer: account)
      with_write { global_notice.set_notice(:personal_billing_trouble) }
    end
  end
end
