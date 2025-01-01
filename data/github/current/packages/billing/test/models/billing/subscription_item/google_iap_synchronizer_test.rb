# typed: true
# frozen_string_literal: true

require "test_helper"
require "googleauth"

require_relative "../../../../../../test/test_helpers/mobile_in_app_purchase_test_helper"

module Billing
  class SubscriptionItem
    class GoogleIapSynchronizerTest < GitHub::BillingTestCase
      include MobileInAppPurchaseTestHelper

      fixtures do
        @copilot_iap_subscription_item = create(:billing_subscription_item, :google_iap, :with_product_uuid)
        @non_iap_subscription_item = create(:billing_subscription_item, :with_product_uuid)
      end

      setup do
        @jan_1_2021 = Time.new(2021, 1, 1, 0, 0, 0)
        google_auth = Google::Auth::DefaultCredentials.new
        Google::Auth::DefaultCredentials.stubs(:make_creds).returns(google_auth)
      end

      context "#initialize" do
        test "sets subscription_item" do
          google_iap_synchronizer = GoogleIapSynchronizer.new(@copilot_iap_subscription_item)

          assert @copilot_iap_subscription_item, google_iap_synchronizer.subscription_item
        end

        test "prevents use from non-IAP SubscriptionItem records" do
          assert_raises_with_message(ArgumentError, "Must have an associated in-app purchase record to sync.") do
            GoogleIapSynchronizer.new(@non_iap_subscription_item)
          end
        end
      end

      test "class-level #call delegates a call to #new and #call" do
        google_iap_synchronizer = GoogleIapSynchronizer.new(@copilot_iap_subscription_item)
        result = GoogleIapSynchronizer::Result.new

        GoogleIapSynchronizer.expects(:new).with(@copilot_iap_subscription_item).returns(google_iap_synchronizer)
        google_iap_synchronizer.expects(:call).returns(result)

        GoogleIapSynchronizer.call(@copilot_iap_subscription_item)
      end

      context "#call" do
        test "does not cancel active subscriptions" do
          Timecop.freeze @jan_1_2021 do
            mock_play_store_client(has_copilot: true)
            result = GoogleIapSynchronizer.call(@copilot_iap_subscription_item)

            assert result.success?
            refute result.cancelled?
            refute result.cancellation_reason
            refute result.subscription_item_result
            assert_empty result.errors
          end
        end

        test "cancels subscriptions not found in Google" do
          Timecop.freeze @jan_1_2021 do
            # Fail request 3 times for all known Android apps
            mock_play_store_client(raise_purchase_token_mismatch: true, times: 3)
            result = GoogleIapSynchronizer.call(@copilot_iap_subscription_item)

            assert result.success?
            assert result.cancelled?
            assert_equal GoogleIapSynchronizer::CancellationReason::NOT_FOUND, result.cancellation_reason
            assert_empty result.errors
          end
        end

        test "cancels test subscriptions" do
          Timecop.freeze @jan_1_2021 do
            # Valid, but in test environment
            mock_play_store_client(environment_name: "Test")

            result = GoogleIapSynchronizer.call(@copilot_iap_subscription_item)

            assert result.success?
            assert result.cancelled?
            assert_equal GoogleIapSynchronizer::CancellationReason::TEST, result.cancellation_reason
            assert_empty result.errors
          end
        end

        test "cancels expired subscriptions" do
          Timecop.freeze @jan_1_2021 do
            mock_play_store_client(has_copilot: false)
            result = GoogleIapSynchronizer.call(@copilot_iap_subscription_item)

            assert result.success?
            assert result.cancelled?
            assert_equal GoogleIapSynchronizer::CancellationReason::EXPIRED, result.cancellation_reason
            assert_empty result.errors
          end
        end
      end
    end
  end
end
