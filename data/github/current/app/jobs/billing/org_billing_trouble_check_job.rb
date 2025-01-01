# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

module Billing
  class OrgBillingTroubleCheckJob < BillingJob
    discard_on ActiveJob::DeserializationError

    def perform(account)
      return unless account.organization? && account.billing_trouble?

      account.admins.each do |admin|
        global_notice = GlobalNoticeNext.new(viewer: admin)
        with_write { global_notice.set_notice(:org_billing_trouble) }
      end
    end
  end
end
