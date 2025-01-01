# typed: true
# frozen_string_literal: true

require "test_helper"

if GitHub.enterprise?
  class EnterpriseLicenseExpirationShutdownHttpTest < GitHub::IntegrationTestCase
    setup do
      @old_expire_at = GitHub::Enterprise.license.expire_at
      GitHub::Enterprise.license_reset!
      GitHub.first_run = false # override enterprise_first_run? state
    end

    teardown do
      GitHub::Enterprise.license.expire_at = @old_expire_at
    end

    test "triggers when the license expiration time is blank" do
      GitHub::Enterprise.license.expire_at = nil
      get "/login"
      assert_response 402
      assert_includes response.body, "Sorry, your GitHub Enterprise license appears to be invalid"
      assert_includes response.body, "and upload it using the"
    end

    test "prompts to download license from enterprise-web for a non-metered license" do
      GitHub::Enterprise.license.expire_at = nil
      get "/login"
      assert_response 402
      assert_includes response.body, "Sorry, your GitHub Enterprise license appears to be invalid"
      assert_select "a[href='#{GitHub.enterprise_web_url}/expired']", text: "download your license"
    end

    test "prompts to download license from the cloud enterprise licensing page for a metered license" do
      GitHub::Enterprise.license.expire_at = nil
      GitHub::Enterprise.license.metered = true
      dotcom_licensing_url = "https://github.com/enterprises/github-inc/enterprise_licensing"
      DotcomConnection.any_instance.stubs(:dotcom_enterprise_licensing_url).returns(dotcom_licensing_url)
      get "/login"
      assert_response 402
      assert_includes response.body, "Sorry, your GitHub Enterprise license appears to be invalid"
      assert_select "a[href='#{dotcom_licensing_url}']", text: "download your license"
    end

    test "does not trigger when license_expire_at is in the future" do
      GitHub::Enterprise.license.expire_at = DateTime.now + 1.day
      get "/login"
      assert_response 200
    end

    test "triggers when license_expire_at is in the past" do
      GitHub::Enterprise.license.expire_at = DateTime.now - 1.hour
      get "/login"
      assert_response 402
      assert_includes response.body, "Sorry, your GitHub Enterprise license expired"
      assert_includes response.body, "Once you have an updated license, you can upload it"
      assert_select "a[href='#{GitHub.enterprise_web_url}/expired']", text: "renew your license"
    end

    test "triggers on metered license when license_expire_at is in the past" do
      GitHub::Enterprise.license.expire_at = DateTime.now - 1.hour
      GitHub::Enterprise.license.metered = true
      dotcom_licensing_url = "https://github.com/enterprises/github-inc/enterprise_licensing"
      DotcomConnection.any_instance.stubs(:dotcom_enterprise_licensing_url).returns(dotcom_licensing_url)

      get "/login"
      assert_response 402
      assert_includes response.body, "Sorry, your GitHub Enterprise license expired"
      assert_includes response.body, "Once you have an updated license, you can upload it"
      assert_select "a[href='#{dotcom_licensing_url}']", text: "renew your license"
    end
  end
end
