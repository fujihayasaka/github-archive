# typed: true
# frozen_string_literal: true

require "test_helper"

class Azure::SubscriptionsControllerTest < GitHub::IntegrationTestCase
  fixtures do
    @owner = create :user, login: "admin-user"
    @customer = create(:customer)
    @org = create(:organization, admin: @owner, customer: @customer)

    @subscriptions = [
      { subscription_id: "80e769f2-ce0f-11ed-afa1-0242ac120002", display_name: "Normal subscription" },
      { subscription_id: "76f609e4-ce0f-11ed-afa1-0242ac120002", display_name: "Pay as you go" },
      { subscription_id: "invalid-id", display_name: "Pay as you run" },
    ]
  end

  setup do
    Billing::Azure::OrgSubscriptionClient.any_instance.stubs(:has_token?).returns(true)
    Billing::Azure::OrgSubscriptionClient.any_instance.stubs(:fetch_subscriptions).returns(@subscriptions)
  end

  context "#index" do
    test "renders the subscription dialog with current subscription preselected" do
      @customer.update(
        azure_subscription_id: "80e769f2-ce0f-11ed-afa1-0242ac120002",
        azure_subscription_name: "Normal subscription"
      )

      as @owner
      get "/azure/organization/#{@org.display_login}/subscriptions"

      assert_response :success
      assert_select "h2", "Connect Azure subscription"
      assert_select "input[id='80e769f2-ce0f-11ed-afa1-0242ac120002'][checked]"
      refute_select "input[id='confirm_subscription_selection'][disabled]"
    end

    test "renders the subscription dialog with no subscription preselected" do
      as @owner
      get "/azure/organization/#{@org.display_login}/subscriptions"

      assert_response :success
      assert_select "h2", "Connect Azure subscription"
      assert_select "input[checked]", false
      assert_select "input[id='confirm_subscription_selection'][disabled]"
    end

    test "renders an error message" do
      Billing::Azure::OrgSubscriptionClient.any_instance.stubs(:fetch_subscriptions).raises(Billing::Azure::SubscriptionClient::UnableToFetchAzureSubscriptionsError)

      as @owner
      get "/azure/organization/#{@org.display_login}/subscriptions"

      assert_response :success
      assert_select "p", "Failed to fetch subscriptions. Please try to login again or contact customer support if you still see an error."
      assert_select "input[id='80e769f2-ce0f-11ed-afa1-0242ac120002']", false
      assert_select "input[id='confirm_subscription_selection'][disabled]"
    end
  end
end if GitHub.billing_enabled?
