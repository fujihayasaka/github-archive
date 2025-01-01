# typed: true
# frozen_string_literal: true

module Billing
  class OrgManualDunningCheckJob < BillingJob
    queue_as :billing

    discard_on ActiveJob::DeserializationError

    def perform(account)
      return unless account.organization? && account.manual_dunning?

      account.admins.each do |admin|
        global_notice = GlobalNoticeNext.new(viewer: admin)
        with_write { global_notice.set_notice(:org_manual_dunning) }
      end
    end
  end
end
