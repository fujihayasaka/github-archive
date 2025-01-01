# typed: true
# frozen_string_literal: true

require "test_helper"

class GlobalNoticeNext::BusinessManualDunningCheckTest < GitHub::TestCase
  fixtures do
    @user = create :user, :verified

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

  context "#should_show_notice?" do
    test "returns true if a user owned business is in manual dunning" do
      @rbi_business.add_owner @user, actor: @rbi_business.owners.first

      check = GlobalNoticeNext::BusinessManualDunningCheck.new viewer: @user

      assert check.should_show_notice?
    end

    test "returns false if no user owned business is in manual dunning" do
      create :business, owners: [@user]

      check = GlobalNoticeNext::BusinessManualDunningCheck.new viewer: @user

      refute check.should_show_notice?
    end
  end
end if GitHub.billing_enabled?
