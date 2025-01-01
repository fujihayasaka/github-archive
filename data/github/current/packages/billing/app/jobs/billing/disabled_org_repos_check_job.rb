# typed: true
# frozen_string_literal: true

module Billing
  class DisabledOrgReposCheckJob < BillingJob
    discard_on ActiveJob::DeserializationError

    def perform(account)
      return unless account.organization? && account.over_plan_limit?

      account.admins.each do |admin|
        global_notice = GlobalNoticeNext.new(viewer: admin)
        with_write { global_notice.set_notice(:disabled_org_repos) }
      end
    end
  end
end
