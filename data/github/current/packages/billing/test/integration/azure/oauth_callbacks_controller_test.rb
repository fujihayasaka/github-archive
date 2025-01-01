# typed: true
# frozen_string_literal: true

require "test_helper"

class Azure::OauthCallbacksControllerTest < GitHub::IntegrationTestCase
  fixtures do
    @owner = create :user, login: "admin-user"
    @customer = create(:customer)
    @org = create(:organization, admin: @owner, customer: @customer)
    @state = Base64.encode64({
      "org_login" => @org.display_login,
      "explicit_tenant_selected" => true,
    }.to_json)
  end

  context "#show" do
    test "redirects to the login controller when not logged in" do
      get "/azure/oauth_callback", params: { code: "123", state: @state }
      assert_includes response.location, "http://github.com/login"
    end

    test "redirects to the authentications controller" do
      as @owner

      get "/azure/oauth_callback", params: { code: "123", state: @state }
      assert_redirected_to "/azure/organization/#{@org.display_login}/authentications?explicit_tenant_selected=true&oauth_code=123"
    end

    test "redirects to root path when there was an error from azure" do
      as @owner

      get "/azure/oauth_callback", params: { error: "things went wrong" }
      assert_redirected_to ""

      assert_includes flash[:error], "Authentication with Azure failed. (things went wrong)"
    end

    test "redirects to root path when there was an error with decoding json" do
      as @owner

      get "/azure/oauth_callback", params: { code: "123", state: "invalid-state" }
      assert_redirected_to ""

      assert_includes flash[:error], "Failed decoding state from Azure"
    end
  end
end if GitHub.billing_enabled?
