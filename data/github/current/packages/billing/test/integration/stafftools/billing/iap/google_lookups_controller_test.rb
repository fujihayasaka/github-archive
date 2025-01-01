# typed: true
# frozen_string_literal: true

require "test_helper"
require "./test/test_helpers/mobile_in_app_purchase_test_helper"

class Stafftools::Billing::Iap::GoogleLookupsControllerTest < GitHub::IntegrationTestCase
  include MobileInAppPurchaseTestHelper

  fixtures do
    @staff = create(:staff_admin_user)
  end

  setup do
    as @staff
  end

  context "#new" do
    test "it renders and prefills purchase token text field" do
      purchase_token = "mona-buy-through-iap-yo"

      get "/stafftools/billing/iap/google_lookups/new?purchase_token=#{purchase_token}"

      assert_template :new
      assert_response :ok
      assert_select "input[id='purchase_token']", value: purchase_token
    end
  end

  context "#create" do
    test "it requires a purchase token" do
      post "/stafftools/billing/iap/google_lookups"

      assert_template :new
      assert_response :ok
      assert_equal "Please provide a purchase token.", flash[:error]
    end

    test "it shows empty response if subscription is not found" do
      mock_play_store_client(raise_purchase_token_mismatch: true, times: 3)

      post "/stafftools/billing/iap/google_lookups", params: { purchase_token: "abc" }

      assert_template :new
      assert_response :ok

      assert_includes response.body, "Mobile::Google::PlayStoreService::PurchaseNotFoundError"
    end

    test "it surfaces response returned from Google" do
      mock_play_store_client

      post "/stafftools/billing/iap/google_lookups", params: { purchase_token: "abc" }

      assert_template :new
      assert_response :ok

      # Ensure a few keys we expect to be in the response are indeeed there
      assert_includes response.body, "subscription_purchase_summary"
      assert_includes response.body, "subscription_purchase"
    end

    test "errors are reported to Failbot" do
      mock_play_store_client(raise_purchase_token_mismatch: true, times: 3)

      post "/stafftools/billing/iap/google_lookups", params: { purchase_token: "abc" }

      last_reported_error_classname = Failbot.exception_classname_from_hash(Failbot.reports.last)
      expected_error_class = Mobile::Google::PlayStoreService::PurchaseNotFoundError

      assert_equal expected_error_class.to_s, last_reported_error_classname
    end
  end
end if GitHub.iap_enabled?
