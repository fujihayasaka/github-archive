# typed: true
# frozen_string_literal: true

require "test_helper"

module Billing
  class BusinessManualDunningCheckJobTest < GitHub::TestCase
    fixtures do
      business_plan_subscription = create \
        :billing_plan_subscription,
        :business_owned,
        balance_in_cents: 1000
      @rbi_business = business_plan_subscription.business
      @rbi_business.customer.update auto_pay_reasons: Set[:india_rbi]
      Billing::ManualDunningPeriod.create \
        created_at: Date.today,
        notification_attempts: 0,
        customer: @rbi_business.customer
    end

    test "displays correct notice to owners of a Business that is in manual dunning" do
      Billing::BusinessManualDunningCheckJob.perform_now @rbi_business

      assert_equal \
        :business_manual_dunning,
        GlobalNoticeNext.new(viewer: @rbi_business.owners.first).current_notice_name
    end
  end
end if GitHub.billing_enabled?
