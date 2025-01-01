# typed: true
# frozen_string_literal: true

module Billing
  class DisabledOrgBillingCheckJob < BillingJob
    queue_as :billing

    discard_on ActiveJob::DeserializationError

    def perform(account)
      return unless account.organization? && account.disabled? && account.paid_plan?

      account.admins.each do |admin|
        global_notice = GlobalNoticeNext.new(viewer: admin)
        with_write { global_notice.set_notice(:disabled_org_billing) }
      end
    end
  end
end
