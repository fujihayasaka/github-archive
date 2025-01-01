# typed: true
# frozen_string_literal: true

require "test_helper"

require_relative "../../../../../../test/test_helpers/mobile_in_app_purchase_test_helper"

module Billing
  class PlanSubscription::AppleIapSynchronizerTest < GitHub::BillingTestCase
    include MobileInAppPurchaseTestHelper

    fixtures do
      @user = create :user, plan: GitHub::Plan.pro
      @subscription = create :billing_plan_subscription, :apple_iap, user: @user
    end

    setup do
      @jan_1_2021 = Time.new(2021, 1, 1, 0, 0, 0)
    end

    test "cancels the subscription if cancellation_date_ms in present in receipt verification response" do
      mock_app_store_service_production_client(valid: false)

      Timecop.freeze @jan_1_2021 do
        service = Billing::PlanSubscription::AppleIapSynchronizer.call(@subscription)
        assert service.success?
      end

      assert_equal "free", @user.reload.plan.name
      refute @subscription.apple_iap_subscription?
    end

    test "cancels the subscription if receipt has expired" do
      mock_app_store_service_production_client(valid: false)

      Timecop.freeze @jan_1_2021 do
        service = Billing::PlanSubscription::AppleIapSynchronizer.call(@subscription)
        assert service.success?
      end

      assert_equal "free", @user.reload.plan.name
      refute @subscription.apple_iap_subscription?
    end

    test "does not change the plan if the plan is not pro" do
      user = create :user, plan: GitHub::Plan.free_with_addons
      subscription = create :billing_plan_subscription, :apple_iap

      mock_app_store_service_production_client(valid: false)

      Timecop.freeze @jan_1_2021 do
        service = Billing::PlanSubscription::AppleIapSynchronizer.call(subscription)
        assert service.success?
      end

      assert user.plan.free_with_addons?
      refute subscription.apple_iap_subscription?
    end

    test "downgrades to free_with_addons when the user has active subscription items" do
      copilot_product_uuid = create(:billing_product_uuid, :copilot, billing_cycle: :month)
      create(:billing_subscription_item, plan_subscription: @subscription, subscribable: copilot_product_uuid, quantity: 1)

      mock_app_store_service_production_client(valid: false)

      Timecop.freeze @jan_1_2021 do
        service = Billing::PlanSubscription::AppleIapSynchronizer.call(@subscription)

        assert service.success?
      end

      assert_equal "free_with_addons", @user.reload.plan.name
      refute @subscription.apple_iap_subscription?
    end

    test "does not cancel the subscription if cancellation_date_ms is nil and expires_date_ms is in the future" do
      mock_app_store_service_production_client

      Timecop.freeze @jan_1_2021 do
        service = Billing::PlanSubscription::AppleIapSynchronizer.call(@subscription)

        assert service.success?
      end

      assert @subscription.plan.pro?
      assert @subscription.apple_iap_subscription?
    end

    test "returns an error message for an invalid receipt id" do
      mock_app_store_service_production_client(raise_transaction_not_found: true)

      service = Billing::PlanSubscription::AppleIapSynchronizer.call(@subscription)

      refute service.success?
      assert_match /Apple receipt is not valid/, service.error_message
    end

    test "nullifies apple_receipt_id and apple_transaction_id for invalid apple iap subscriptions" do
      mock_app_store_service_production_client(raise_transaction_not_found: true)

      service = Billing::PlanSubscription::AppleIapSynchronizer.call(@subscription)

      assert_nil @subscription.apple_receipt_id
      assert_nil @subscription.apple_transaction_id
    end

    context "IAP sandbox environment" do
      test "nullifies apple_receipt_id and apple_transaction_id and does not downgrade to free" do
        mock_app_store_service_production_client(environment_name: "Sandbox", valid: false)

        Timecop.freeze @jan_1_2021 do
          service = Billing::PlanSubscription::AppleIapSynchronizer.call(@subscription)
          assert service.success?
        end

        assert @user.plan.pro?
        refute @subscription.apple_iap_subscription?
      end
    end
  end
end
