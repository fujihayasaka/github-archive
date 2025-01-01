# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::GoogleSubscriptionTest < GitHub::BillingTestCase
  include GitHub::LoggerHelper

  fixtures do
    @user = create(:user)
    @sub_item = create(:billing_subscription_item, account: @user)
    @sub_item2 = create(:billing_subscription_item, account: @user)
    @iap_sub_item = create(:billing_subscription_item, :google_iap, account: @user)
  end

  setup do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
  end

  context "validation and persistence" do
    test "purchase_token is required" do
      google_subscription = build(:billing_google_subscription, purchase_token: nil)

      refute google_subscription.valid?
      assert_includes_match(/Purchase token can't be blank/, google_subscription.errors.full_messages)
    end

    test "subscription_item is required" do
      google_subscription = build(:billing_google_subscription)

      refute google_subscription.valid?
      assert_includes_match(/Subscription item must exist/, google_subscription.errors.full_messages)
    end

    test "purchase_token must be unique" do
      saved_subscription = create(
        :billing_google_subscription,
        subscription_item: @sub_item,
        purchase_token: "123"
      )

      assert saved_subscription.persisted?

      google_subscription = build(
        :billing_google_subscription,
        subscription_item: @sub_item2,
        purchase_token: "123"
      )

      refute google_subscription.valid?
      assert_includes_match(/Purchase token has already been taken/, google_subscription.errors.full_messages)
    end

    test "purchase_token must be case insensitive unique" do
      saved_subscription = create(
        :billing_google_subscription,
        subscription_item: @sub_item,
        purchase_token: "123abc"
      )

      assert saved_subscription.persisted?

      google_subscription = build(
        :billing_google_subscription,
        subscription_item: @sub_item2,
        purchase_token: "123ABC"
      )

      refute google_subscription.valid?
      assert_includes_match(/Purchase token has already been taken/, google_subscription.errors.full_messages)
    end

    test "subscription_item must be unique" do
      saved_subscription = create(
        :billing_google_subscription,
        subscription_item: @sub_item,
        purchase_token: "123"
      )

      assert saved_subscription.persisted?

      google_subscription = build(
        :billing_google_subscription,
        subscription_item: @sub_item,
        purchase_token: "456"
      )

      refute google_subscription.valid?
      assert_includes_match(/Subscription item has already been taken/, google_subscription.errors.full_messages)
    end

    test "#save returns true when validations are met" do
      google_subscription = build(
        :billing_google_subscription,
        subscription_item: @sub_item,
        purchase_token: "123"
      )

      assert google_subscription.save
    end
  end

  context "destruction" do
    test "destroying associated SubscriptionItem destroys the associated GoogleSubscription" do
      google_subscription = create(
        :billing_google_subscription,
        subscription_item: @sub_item,
        purchase_token: "123"
      )

      assert google_subscription.persisted?
      assert @sub_item.destroy
      assert google_subscription.destroyed?
    end

    test "logs destruction when subscription is cancelled" do
      # Ensure staged data is correct
      assert @iap_sub_item.google_subscription

      google_subscription_id = @iap_sub_item.google_subscription.id
      purchase_token = @iap_sub_item.google_subscription.purchase_token

      logs = capture_logs do
        result = @iap_sub_item.cancel!(force: true, allow_cancelling_iap: true)

        # Double check that the cancellation was successful.
        assert result.result.success
      end

      # Make sure we bust anything cached since we cancelled the subscription.
      @iap_sub_item.reload

      # We should have no GoogleSubscription record associated with the SubscriptionItem record since it has been cancelled.
      assert_nil @iap_sub_item.google_subscription

      # We are expecting a log message to be generated when the GoogleSubscription record is destroyed, such as:
      #   InstrumentationScope="GitHub" SeverityText="INFO" Body="A Billing::GoogleSubscription record is being destroyed."
      #   code.namespace="Billing::GoogleSubscription" code.function="destroy" gh.google_subscription.id="7"
      #   gh.google_subscription.subscription_item_id="11"
      #   gh.google_subscription.purchase_token="92a687ea-8777-4dcc-adee-b17c1dac8c6a"
      assert_match "A Billing::GoogleSubscription record is being destroyed.", logs
      assert_match "gh.google_subscription.subscription_item_id=\"#{@iap_sub_item.id}\"", logs
      assert_match "gh.google_subscription.purchase_token=\"#{purchase_token}\"", logs
      assert_match "gh.google_subscription.id=\"#{google_subscription_id}\"", logs
      assert_match "gh.plan_subscription.user_id=\"#{@iap_sub_item.plan_subscription.user_id}\"", logs

      # Also double check that we have a dogstats increment for the destruction of the AppleSubscription record.
      assert_equal 1, GitHub.dogstats.increments("billing.google_subscription", tags: ["action:destroy"]).length
    end
  end
end
