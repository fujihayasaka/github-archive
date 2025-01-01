# typed: true
# frozen_string_literal: true

module Billing
  class BusinessManualDunningCheckJob < BillingJob
    discard_on ActiveJob::DeserializationError

    def perform(account)
      return unless account.present? && account.manual_dunning?

      account.owners.each do |owner|
        global_notice = GlobalNoticeNext.new(viewer: owner)
        with_write { global_notice.set_notice(:business_manual_dunning) }
      end
    end
  end
end
