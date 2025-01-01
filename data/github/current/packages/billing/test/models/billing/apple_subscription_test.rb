# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::AppleSubscriptionTest < GitHub::BillingTestCase
  include GitHub::LoggerHelper

  fixtures do
    @user = create(:user)
    @sub_item = create(:billing_subscription_item, account: @user)
    @sub_item2 = create(:billing_subscription_item, account: @user)
    @iap_sub_item = create(:billing_subscription_item, :iap, account: @user)
  end

  setup do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
  end

  context "validation and persistence" do
    test "original_transaction_id is required" do
      apple_subscription = build(:billing_apple_subscription, original_transaction_id: nil)

      refute apple_subscription.valid?
      assert_includes_match(/Original transaction can't be blank/, apple_subscription.errors.full_messages)
    end

    test "subscription_item is required" do
      apple_subscription = build(:billing_apple_subscription)

      refute apple_subscription.valid?
      assert_includes_match(/Subscription item must exist/, apple_subscription.errors.full_messages)
    end

    test "original_transaction_id must be unique" do
      saved_subscription = create(
        :billing_apple_subscription,
        subscription_item: @sub_item,
        original_transaction_id: "123"
      )

      assert saved_subscription.persisted?

      apple_subscription = build(
        :billing_apple_subscription,
        subscription_item: @sub_item2,
        original_transaction_id: "123"
      )

      refute apple_subscription.valid?
      assert_includes_match(/Original transaction has already been taken/, apple_subscription.errors.full_messages)
    end

    test "subscription_item must be unique" do
      saved_subscription = create(
        :billing_apple_subscription,
        subscription_item: @sub_item,
        original_transaction_id: "123"
      )

      assert saved_subscription.persisted?

      apple_subscription = build(
        :billing_apple_subscription,
        subscription_item: @sub_item,
        original_transaction_id: "456"
      )

      refute apple_subscription.valid?
      assert_includes_match(/Subscription item has already been taken/, apple_subscription.errors.full_messages)
    end

    test "#save returns true when validations are met" do
      apple_subscription = build(
        :billing_apple_subscription,
        subscription_item: @sub_item,
        original_transaction_id: "123"
      )

      assert apple_subscription.save
    end
  end

  context "destruction" do
    test "destroying associated SubscriptionItem destroys the associated AppleSubscription" do
      apple_subscription = create(
        :billing_apple_subscription,
        subscription_item: @sub_item,
        original_transaction_id: "123"
      )

      assert apple_subscription.persisted?
      assert @sub_item.destroy
      assert apple_subscription.destroyed?
    end

    test "logs destruction when subscription is cancelled" do
      # Ensure staged data is correct
      assert @iap_sub_item.apple_subscription

      apple_subscription_id = @iap_sub_item.apple_subscription.id
      original_transaction_id = @iap_sub_item.apple_subscription.original_transaction_id

      logs = capture_logs do
        result = @iap_sub_item.cancel!(force: true, allow_cancelling_iap: true)

        # Double check that the cancellation was successful.
        assert result.result.success
      end

      # Make sure we bust anything cached since we cancelled the subscription.
      @iap_sub_item.reload

      # We should have no AppleSubscription record associated with the SubscriptionItem record since it has been cancelled.
      assert_nil @iap_sub_item.apple_subscription

      # We are expecting a log message to be generated when the AppleSubscription record is destroyed, such as:
      #   InstrumentationScope="GitHub" SeverityText="INFO" Body="A Billing::AppleSubscription record is being destroyed."
      #   code.namespace="Billing::AppleSubscription" code.function="destroy" gh.apple_subscription.id="7"
      #   gh.apple_subscription.subscription_item_id="11"
      #   gh.apple_subscription.original_transaction_id="92a687ea-8777-4dcc-adee-b17c1dac8c6a"
      assert_match "A Billing::AppleSubscription record is being destroyed.", logs
      assert_match "gh.apple_subscription.subscription_item_id=\"#{@iap_sub_item.id}\"", logs
      assert_match "gh.apple_subscription.original_transaction_id=\"#{original_transaction_id}\"", logs
      assert_match "gh.apple_subscription.id=\"#{apple_subscription_id}\"", logs
      assert_match "gh.plan_subscription.user_id=\"#{@iap_sub_item.plan_subscription.user_id}\"", logs

      # Also double check that we have a dogstats increment for the destruction of the AppleSubscription record.
      assert_equal 1, GitHub.dogstats.increments("billing.apple_subscription", tags: ["action:destroy"]).length
    end
  end
end
