# typed: true
# frozen_string_literal: true

module Billing
  class DisabledPersonalBillingCheckJob < BillingJob
    queue_as :billing

    discard_on ActiveJob::DeserializationError

    resolve_tenant_context do |account|
      if account.enterprise?
        account
      else
        account.business
      end
    end

    def perform(account)
      return unless account.disabled? && account.paid_plan?

      if account.organization?
        account.admins.each do |admin|
          global_notice = GlobalNoticeNext.new(viewer: admin)
          with_write { global_notice.set_notice(:disabled_personal_billing) }
        end
      else
        with_write { account.global_notice.set(:disabled_personal_billing) }
      end
    end
  end
end
