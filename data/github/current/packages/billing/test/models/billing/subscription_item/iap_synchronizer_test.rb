# typed: true
# frozen_string_literal: true

require "test_helper"

require_relative "../../../../../../test/test_helpers/mobile_in_app_purchase_test_helper"

module Billing
  class SubscriptionItem
    class IapSynchronizerTest < GitHub::BillingTestCase
      include MobileInAppPurchaseTestHelper

      fixtures do
        @copilot_iap_subscription_item = create(:billing_subscription_item, :iap, :with_product_uuid)
        @non_iap_subscription_item = create(:billing_subscription_item, :with_product_uuid)
      end

      setup do
        @jan_1_2021 = Time.new(2021, 1, 1, 0, 0, 0)
      end

      context "#initialize" do
        test "sets subscription_item" do
          iap_synchronizer = IapSynchronizer.new(@copilot_iap_subscription_item)

          assert @copilot_iap_subscription_item, iap_synchronizer.subscription_item
        end

        test "prevents use from non-IAP SubscriptionItem records" do
          assert_raises_with_message(ArgumentError, "Must have an associated in-app purchase record to sync.") do
            IapSynchronizer.new(@non_iap_subscription_item)
          end
        end
      end

      test "class-level #call delegates a call to #new and #call" do
        iap_synchronizer = IapSynchronizer.new(@copilot_iap_subscription_item)
        result = IapSynchronizer::Result.new

        IapSynchronizer.expects(:new).with(@copilot_iap_subscription_item).returns(iap_synchronizer)
        iap_synchronizer.expects(:call).returns(result)

        IapSynchronizer.call(@copilot_iap_subscription_item)
      end

      context "#call" do
        test "does not cancel active subscriptions" do
          mock_app_store_service_production_client(has_copilot: true)

          Timecop.freeze @jan_1_2021 do
            result = IapSynchronizer.call(@copilot_iap_subscription_item)

            assert result.success?
            refute result.cancelled?
            refute result.cancellation_reason
            refute result.subscription_item_result
            assert_empty result.errors
          end
        end

        test "cancels subscriptions not found in Apple" do
          mock_app_store_service_production_client(raise_transaction_not_found: true)

          Timecop.freeze @jan_1_2021 do
            result = IapSynchronizer.call(@copilot_iap_subscription_item)

            assert result.success?
            assert result.cancelled?
            assert_equal IapSynchronizer::CancellationReason::NOT_FOUND, result.cancellation_reason
            assert_empty result.errors
          end
        end

        test "cancels sandbox subscriptions" do
          # Valid, but in sandbox environment
          mock_app_store_service_production_client(environment_name: "Sandbox")

          Timecop.freeze @jan_1_2021 do
            result = IapSynchronizer.call(@copilot_iap_subscription_item)

            assert result.success?
            assert result.cancelled?
            assert_equal IapSynchronizer::CancellationReason::SANDBOX, result.cancellation_reason
            assert_empty result.errors
          end
        end

        test "cancels expired subscriptions" do
          mock_app_store_service_production_client(valid: false)

          Timecop.freeze @jan_1_2021 do
            result = IapSynchronizer.call(@copilot_iap_subscription_item)

            assert result.success?
            assert result.cancelled?
            assert_equal IapSynchronizer::CancellationReason::EXPIRED, result.cancellation_reason
            assert_empty result.errors
          end
        end
      end
    end
  end
end
