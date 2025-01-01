# typed: true
# frozen_string_literal: true

require "test_helper"

class Azure::TenantsControllerTest < GitHub::IntegrationTestCase
  fixtures do
    @owner = create :user, login: "admin-user"
    @customer = create(:customer)
    @org = create(:organization, admin: @owner, customer: @customer)

    @tenants = [
      {
        tenant_id: "123",
        display_name: "Fake Inc",
        redirect_url: "https://example.com",
      },
      {
        tenant_id: "456",
        display_name: "ACME Inc",
        redirect_url: "https://example.com",
      },
    ]
  end

  setup do
    Billing::Azure::OrgSubscriptionClient.any_instance.stubs(:has_token?).returns(true)
    Billing::Azure::OrgSubscriptionClient.any_instance.stubs(:fetch_tenants).returns(@tenants)
  end

  context "#index" do
    test "redirects to the login controller when not logged in" do
      get "/azure/organization/#{@org.display_login}/tenants"
      assert_includes response.location, "http://github.com/login"
    end

    test "renders the tenant dialog with list of tenants" do
      as @owner
      get "/azure/organization/#{@org.display_login}/tenants"

      assert_response :success
      assert_select "span", "Fake Inc"
      assert_select "span", "ACME Inc"
    end

    test "renders the tenant dialog with an error" do
      Billing::Azure::OrgSubscriptionClient.any_instance.stubs(:fetch_tenants).raises(Billing::Azure::SubscriptionClient::UnableToFetchAzureSubscriptionsError)

      as @owner
      get "/azure/organization/#{@org.display_login}/tenants"

      assert_response :success
      assert_select "p", "Failed to fetch tenants. Please try to login again or contact customer support if you still see an error."
    end
  end
end if GitHub.billing_enabled?
