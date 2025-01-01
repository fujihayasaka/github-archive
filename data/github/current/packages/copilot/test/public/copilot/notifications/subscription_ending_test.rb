# typed: true
# frozen_string_literal: true

require "test_helper"

class CopilotNotificationsSubscriptionEndingTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags

  fixtures do
    @plan_subscription = create(:billing_plan_subscription, :zuora)
    @user = @plan_subscription.user

    @copilot_monthly_product_uuid = create(:billing_product_uuid, :copilot, billing_cycle: :month)
    @copilot_yearly_product_uuid = create(:billing_product_uuid, :copilot, billing_cycle: :year)
  end

  test "does not send for 5 days" do
    @copilot_product_uuid = create(:billing_product_uuid, :copilot, billing_cycle: :month)
    jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")
    march_4th = GitHub::Billing.date_in_timezone Date.parse("2023-03-04")
    next_billing_date = GitHub::Billing.date_in_timezone Date.parse("2023-03-09")
    user = create(:credit_card_user)

    Billing::SubscriptionItem.any_instance.stubs(:next_billing_date).returns(next_billing_date)

    # User signs up
    subscription_item = travel_to jan_1st do
      create(:billing_subscription_item,
        plan_subscription: create(:billing_plan_subscription, user: user),
        subscribable: @copilot_product_uuid,
        quantity: 1)
    end

    # User cancels
    travel_to march_4th do
      create :billing_pending_subscription_item_change,
        subscribable: @copilot_product_uuid,
        free_trial: true,
        pending_plan_change: create(:billing_pending_plan_change, user: user),
        quantity: 0
      public_subscription_item = Billing::Public::SubscriptionItem.new(subscription_item)

      assert_equal 5, public_subscription_item.days_left_on_subscription

      copilot_user = Copilot::User.new(user)
      notification = Copilot::Notifications::SubscriptionEnding.new(copilot_user)
      refute notification.send_condition
    end
  end

  test "sends for 3 days" do
    @copilot_product_uuid = create(:billing_product_uuid, :copilot, billing_cycle: :month)
    jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")
    march_4th = GitHub::Billing.date_in_timezone Date.parse("2023-03-04")
    next_billing_date = GitHub::Billing.date_in_timezone Date.parse("2023-03-07")
    user = create(:credit_card_user)

    Billing::SubscriptionItem.any_instance.stubs(:next_billing_date).returns(next_billing_date)

    # User signs up
    subscription_item = travel_to jan_1st do
      create :billing_subscription_item,
        plan_subscription: create(:billing_plan_subscription, user: user),
        subscribable: @copilot_product_uuid,
        quantity: 1
    end

    # User cancels
    travel_to march_4th do
      create :billing_pending_subscription_item_change,
        subscribable: @copilot_product_uuid,
        free_trial: true,
        pending_plan_change: create(:billing_pending_plan_change, user: user),
        quantity: 0
      public_subscription_item = Billing::Public::SubscriptionItem.new(subscription_item)

      assert_equal 3, public_subscription_item.days_left_on_subscription

      copilot_user = Copilot::User.new(user)
      notification = Copilot::Notifications::SubscriptionEnding.new(copilot_user)
      assert notification.send_condition
      assert_equal "Your access to GitHub Copilot ends in three days.", notification.message
    end
  end

  test "sends for 1 days" do
    @copilot_product_uuid = create(:billing_product_uuid, :copilot, billing_cycle: :month)
    jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")
    march_4th = GitHub::Billing.date_in_timezone Date.parse("2023-03-04")
    next_billing_date = GitHub::Billing.date_in_timezone Date.parse("2023-03-05")
    user = create(:credit_card_user)

    Billing::SubscriptionItem.any_instance.stubs(:next_billing_date).returns(next_billing_date)

    # User signs up
    subscription_item = travel_to jan_1st do
      create :billing_subscription_item,
        plan_subscription: create(:billing_plan_subscription, user: user),
        subscribable: @copilot_product_uuid,
        quantity: 1
    end

    # User cancels
    travel_to march_4th do
      create :billing_pending_subscription_item_change,
        subscribable: @copilot_product_uuid,
        free_trial: true,
        pending_plan_change: create(:billing_pending_plan_change, user: user),
        quantity: 0
      public_subscription_item = Billing::Public::SubscriptionItem.new(subscription_item)

      assert_equal 1, public_subscription_item.days_left_on_subscription

      copilot_user = Copilot::User.new(user)
      notification = Copilot::Notifications::SubscriptionEnding.new(copilot_user)
      assert notification.send_condition
      assert_equal "Your access to GitHub Copilot ends in one day.", notification.message
    end
  end

  test "does not send for 1 days if already sent for 3" do
    @copilot_product_uuid = create(:billing_product_uuid, :copilot, billing_cycle: :month)
    jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")
    march_4th = GitHub::Billing.date_in_timezone Date.parse("2023-03-04")
    next_billing_date = GitHub::Billing.date_in_timezone Date.parse("2023-03-05")
    user = create(:credit_card_user)

    Billing::SubscriptionItem.any_instance.stubs(:next_billing_date).returns(next_billing_date)

    # User signs up
    subscription_item = travel_to jan_1st do
      create :billing_subscription_item,
        plan_subscription: create(:billing_plan_subscription, user: user),
        subscribable: @copilot_product_uuid,
        quantity: 1
    end

    # User cancels
    travel_to march_4th do
      create :billing_pending_subscription_item_change,
        subscribable: @copilot_product_uuid,
        free_trial: true,
        pending_plan_change: create(:billing_pending_plan_change, user: user),
        quantity: 0
      public_subscription_item = Billing::Public::SubscriptionItem.new(subscription_item)

      assert_equal 1, public_subscription_item.days_left_on_subscription

      copilot_user = Copilot::User.new(user)
      notification = Copilot::Notifications::SubscriptionEnding.new(copilot_user)
      create(:copilot_editor_notification, notification_id: notification.notification_id, user: user)
      refute notification.send_condition
    end
  end
end if GitHub.copilot_enabled?
