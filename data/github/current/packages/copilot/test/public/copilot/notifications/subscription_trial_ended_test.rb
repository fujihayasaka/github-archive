# typed: true
# frozen_string_literal: true

require "test_helper"

class CopilotNotificationsSubscriptionTrialEndedTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags

  fixtures do
    @plan_subscription = create(:billing_plan_subscription, :zuora)
    @user = @plan_subscription.user

    @copilot_monthly_product_uuid = create(:billing_product_uuid, :copilot, billing_cycle: :month)
    @copilot_yearly_product_uuid = create(:billing_product_uuid, :copilot, billing_cycle: :year)
  end

  context "send_condition("")" do
    test "doesn't send if already existing" do
      notification = Copilot::Notifications::SubscriptionTrialEnded.new(Copilot::User.new(@user))
      refute notification.existing?

      create(:copilot_editor_notification, notification_id: notification.notification_id, user: @user)
      assert notification.existing?
      refute notification.send_condition
    end

    test "returns false for subscription with no trial" do
      create(:billing_subscription_item, :paid,
        plan_subscription: @plan_subscription,
        subscribable: @copilot_monthly_product_uuid
      )
      notification = Copilot::Notifications::SubscriptionTrialEnded.new(Copilot::User.new(@user))

      refute notification.send_condition
    end

    test "returns false for subscription with trial but not ending today" do
      create(:billing_subscription_item, :paid,
        plan_subscription: @plan_subscription,
        subscribable: @copilot_monthly_product_uuid,
        free_trial_ends_on: 10.days.from_now,
      )
      notification = Copilot::Notifications::SubscriptionTrialEnded.new(Copilot::User.new(@user))

      refute notification.send_condition
    end

    test "returns true for subscription with trial ending today" do
      create(:billing_subscription_item, :paid,
        plan_subscription: @plan_subscription,
        subscribable: @copilot_monthly_product_uuid,
        free_trial_ends_on: Date.today,
      )
      notification = Copilot::Notifications::SubscriptionTrialEnded.new(Copilot::User.new(@user))

      assert notification.send_condition
    end

    test "shows notification if they haven't signed in before" do
      create(:billing_subscription_item, :paid,
        plan_subscription: @plan_subscription,
        subscribable: @copilot_monthly_product_uuid,
        free_trial_ends_on: Date.today - 5.days,
      )
      notification = Copilot::Notifications::SubscriptionTrialEnded.new(Copilot::User.new(@user))

      assert notification.send_condition
    end

    test "doesnt show notification if the have signed in before" do
      create(:billing_subscription_item, :paid,
        plan_subscription: @plan_subscription,
        subscribable: @copilot_monthly_product_uuid,
        free_trial_ends_on: Date.today - 5.days,
      )
      notification = Copilot::Notifications::SubscriptionTrialEnded.new(Copilot::User.new(@user))
      create(:copilot_editor_notification, notification_id: notification.notification_id, user: @user)
      refute notification.send_condition
    end
  end
end if GitHub.copilot_enabled?
