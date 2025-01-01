# typed: true
# frozen_string_literal: true

require "test_helper"

class Azure::AuthenticationsControllerTest < GitHub::IntegrationTestCase
  fixtures do
    @owner = create :user, login: "admin-user"
    @customer = create(:customer)
    @org = create(:organization, admin: @owner, customer: @customer)
    @one_tenant = [{ tenant_id: "123", display_name: "Fake Inc", redirect_url: "https://example.com" }]
    @multiple_tenants = [
      { tenant_id: "123", display_name: "Fake Inc", redirect_url: "https://example.com" },
      { tenant_id: "786", display_name: "ACME Inc", redirect_url: "https://example.com/1" },
    ]
  end

  setup do
    Billing::Azure::OrgSubscriptionClient.any_instance.stubs(:fetch_and_store_token)
  end

  context "#show" do
    test "redirects to the org billing page when no code given" do
      as @owner
      get "/azure/organization/#{@org.display_login}/authentications"
      assert_response :redirect
      assert_redirected_to settings_org_billing_path(@org)
    end

    test "redirects to the org billing page when there was a error in client" do
      Billing::Azure::OrgSubscriptionClient.any_instance.stubs(:fetch_tenants).raises(Faraday::ClientError.new("error"))
      as @owner
      get "/azure/organization/#{@org.display_login}/authentications?oauth_code=123"
      assert_response :redirect
      assert_redirected_to settings_org_billing_path(@org)
      assert_includes flash[:error], "Failed to fetch authentication information from Azure. Please try again."
    end

    test "redirects to the org billing page with open tenant dialog when multiple tenants" do
      Billing::Azure::OrgSubscriptionClient.any_instance.stubs(:fetch_tenants).returns(@multiple_tenants)
      as @owner
      get "/azure/organization/#{@org.display_login}/authentications?oauth_code=123"
      assert_response :redirect
      assert_redirected_to settings_org_billing_path(@org, anchor: "open_tenant_dialog")
    end

    test "redirects to the org billing page with open subscription dialog when only one tenant" do
      Billing::Azure::OrgSubscriptionClient.any_instance.stubs(:fetch_tenants).returns(@one_tenant)
      as @owner
      get "/azure/organization/#{@org.display_login}/authentications?oauth_code=123"
      assert_response :redirect
      assert_redirected_to settings_org_billing_path(@org, anchor: "open_dialog")
    end
  end
end if GitHub.billing_enabled?
