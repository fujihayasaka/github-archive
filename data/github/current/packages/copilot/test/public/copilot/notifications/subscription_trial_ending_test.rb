# typed: true
# frozen_string_literal: true

require "test_helper"

class CopilotNotificationsSubscriptionTrialEndingTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags

  fixtures do
    @plan_subscription = create(:billing_plan_subscription, :zuora)
    @user = @plan_subscription.user

    @copilot_monthly_product_uuid = create(:billing_product_uuid, :copilot, billing_cycle: :month)
    @copilot_yearly_product_uuid = create(:billing_product_uuid, :copilot, billing_cycle: :year)
  end

  test "returns false for subscription with trial but not ending in next three days" do
    create(:billing_subscription_item, :paid,
      plan_subscription: @plan_subscription,
      subscribable: @copilot_monthly_product_uuid,
      free_trial_ends_on: 60.days.from_now,
    )
    notification = Copilot::Notifications::SubscriptionTrialEnding.new(Copilot::User.new(@user))

    refute notification.send_condition
  end
end if GitHub.copilot_enabled?
