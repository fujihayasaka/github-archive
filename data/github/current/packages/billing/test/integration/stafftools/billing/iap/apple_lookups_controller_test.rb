# typed: true
# frozen_string_literal: true

require "test_helper"
require "./test/test_helpers/mobile_in_app_purchase_test_helper"

class Stafftools::Billing::Iap::AppleLookupsControllerTest < GitHub::IntegrationTestCase
  include MobileInAppPurchaseTestHelper

  fixtures do
    @staff = create(:staff_admin_user)
  end

  setup do
    as @staff
  end

  context "#new" do
    test "it renders and prefills transaction id text field" do
      transaction_id = "mona-buy-through-iap-yo"

      get "/stafftools/billing/iap/apple_lookups/new?transaction_id=#{transaction_id}"

      assert_template :new
      assert_response :ok
      assert_select "input[id='transaction_id']", value: transaction_id
    end
  end

  context "#create" do
    test "it requires a Transaction ID" do
      post "/stafftools/billing/iap/apple_lookups"

      assert_template :new
      assert_response :ok
      assert_equal "Please provide a Transaction ID.", flash[:error]
    end

    test "it surfaces errors returned from Apple" do
      mock_app_store_service_production_client(raise_transaction_not_found: true)

      post "/stafftools/billing/iap/apple_lookups", params: { transaction_id: "abc" }

      assert_template :new
      assert_response :ok

      assert_includes response.body, "Mobile::Apple::AppStoreClient::InvalidTransactionIdError"
    end

    test "it surfaces response returned from Apple" do
      mock_app_store_service_production_client

      post "/stafftools/billing/iap/apple_lookups", params: { transaction_id: "1000000686674806" }

      assert_template :new
      assert_response :ok

      # Ensure a few keys we expect to be in the response are indeeed there
      assert_includes response.body, "subscription_summary"
      assert_includes response.body, "status_response"
      assert_includes response.body, "last_transactions"
      assert_includes response.body, "subscription_group_identifier"
    end

    test "errors are reported to Failbot" do
      mock_app_store_service_production_client(raise_transaction_not_found: true)

      post "/stafftools/billing/iap/apple_lookups", params: { transaction_id: "abc" }

      last_reported_error_classname = Failbot.exception_classname_from_hash(Failbot.reports.last)
      expected_error_class = Mobile::Apple::AppStoreClient::InvalidTransactionIdError

      assert_equal expected_error_class.to_s, last_reported_error_classname
    end
  end
end if GitHub.iap_enabled?
