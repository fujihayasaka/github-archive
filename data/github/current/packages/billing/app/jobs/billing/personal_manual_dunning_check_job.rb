# typed: true
# frozen_string_literal: true

module Billing
  class PersonalManualDunningCheckJob < BillingJob
    discard_on ActiveJob::DeserializationError

    def perform(account)
      return unless account.user? && account.manual_dunning?

      global_notice = GlobalNoticeNext.new(viewer: account)
      with_write { global_notice.set_notice(:personal_manual_dunning) }
    end
  end
end
