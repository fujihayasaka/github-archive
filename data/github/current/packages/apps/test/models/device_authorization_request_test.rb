# typed: true
# frozen_string_literal: true

require "test_helper"

class DeviceAuthorizationRequestTest < GitHub::TestCase
  fixtures do
    @application = create(:oauth_application, device_flow_enabled: true)
  end

  context "failures" do
    test "OAuth application is suspended" do
      @application.update(state: :suspended); @application.reload
      assert_predicate @application, :suspended?

      response = process(@application)

      error_description = "Your application has been suspended. Please visit #{Rails.application.routes.url_helpers.contact_url(host: GitHub.host_name_with_tenant)}."
      expected = {
        error: :application_suspended,
        error_description:  error_description,
        error_uri: DeviceAuthorizationRequest::OAUTH_APPLICATION_SUSPENDED,
      }

      assert_same_hash expected, response
    end

    test "integration is suspended" do
      integration = create(:integration)
      admin = create(:staff_admin_user)
      integration.suspend(actor: admin, reason: "to make the tests green")
      assert_predicate integration.reload, :suspended?

      response = process(integration)

      error_description = "Your application has been suspended. Please visit #{Rails.application.routes.url_helpers.contact_url(host: GitHub.host_name_with_tenant)}."
      expected = {
        error: :application_suspended,
        error_description:  error_description,
        error_uri: DeviceAuthorizationRequest::GITHUB_APP_SUSPENDED,
      }

      assert_same_hash expected, response
    end

    test "scopes provided for an OAuthApplication are invalid" do
      scope = "foo,repo,bar"

      response = process(@application, { scope: scope })

      expected = {
        error: :invalid_scope,
        error_description: "The scopes requested are invalid: bar and foo.",
        error_uri: GitHub.developer_help_url,
      }

      assert_same_hash expected, response
    end

    test "device authorization grant failed to be created" do
      DeviceAuthorizationGrant.stubs(:create!).raises(ActiveRecord::RecordInvalid)

      response = process(@application)

      expected = {
        error: :request_failed,
        error_description: "The request failed to be processed, please try again",
      }

      assert_same_hash expected, response
    end

    test "device authorization device code failed to be redeemed" do
      DeviceAuthorizationGrant.any_instance.stubs(:redeem_device_code!).raises(ActiveRecord::RecordInvalid)

      response = process(@application)

      expected = {
        error: :request_failed,
        error_description: "The request failed to be processed, please try again",
      }

      assert_same_hash expected, response
    end

    test "device flow is disabled" do
      application = create(:integration, device_flow_enabled: false)
      response = process(application)

      expected = {
        error: :device_flow_disabled,
        error_description: "Device Flow must be explicitly enabled for this App",
        error_uri: GitHub.developer_help_url,
      }

      assert_same_hash expected, response
    end
  end

  test "creates a device authorization grant for an OauthApplication" do
    Timecop.freeze do
      response = assert_difference "DeviceAuthorizationGrant.count", 1 do
        process(@application)
      end

      device_authorization_grant = DeviceAuthorizationGrant.last

      expected = {
        device_code: response[:device_code],
        user_code: device_authorization_grant.user_code,
        verification_uri: "#{GitHub.url}/login/device",
        expires_in: device_authorization_grant.expires_in,
        interval: DeviceAuthorizationGrant::INTERVAL
      }

      assert_same_hash expected, response
      hashed_device_code = DeviceAuthorizationGrant.hash_for(response[:device_code])

      assert_equal device_authorization_grant.hashed_device_code, hashed_device_code
      assert_equal device_authorization_grant.device_code_last_eight, response[:device_code].last(8)
      assert_equal "1.2.3.4", device_authorization_grant.ip
    end
  end

  test "creates a device authorization grant for an Integration" do
    integration = create(:integration, device_flow_enabled: true)

    Timecop.freeze do
      response = assert_difference "DeviceAuthorizationGrant.count", 1 do
        process(integration)
      end

      device_authorization_grant = DeviceAuthorizationGrant.last

      expected = {
        device_code: response[:device_code],
        user_code: device_authorization_grant.user_code,
        verification_uri: "#{GitHub.url}/login/device",
        expires_in: device_authorization_grant.expires_in,
        interval: DeviceAuthorizationGrant::INTERVAL
      }

      assert_same_hash expected, response
      hashed_device_code = DeviceAuthorizationGrant.hash_for(response[:device_code])

      assert_equal device_authorization_grant.hashed_device_code, hashed_device_code
      assert_equal device_authorization_grant.device_code_last_eight, response[:device_code].last(8)
    end
  end

  test "grant response includes dotcom host in verification_uri for dotcom requests" do
    integration = create(:integration, device_flow_enabled: true)
    GitHub.stubs(:multi_tenant_enterprise?).returns(false)

    Timecop.freeze do
      response = assert_difference "DeviceAuthorizationGrant.count", 1 do
        process(integration)
      end

      device_authorization_grant = DeviceAuthorizationGrant.last

      expected = {
        device_code: response[:device_code],
        user_code: device_authorization_grant.user_code,
        verification_uri: "#{GitHub.url}/login/device",
        expires_in: device_authorization_grant.expires_in,
        interval: DeviceAuthorizationGrant::INTERVAL
      }

      assert_same_hash expected, response
      hashed_device_code = DeviceAuthorizationGrant.hash_for(response[:device_code])

      assert_equal device_authorization_grant.hashed_device_code, hashed_device_code
      assert_equal device_authorization_grant.device_code_last_eight, response[:device_code].last(8)
    end
  end

  test "grant response includes tenant host name in verification_uri for proxima requests" do
    integration = create(:integration, device_flow_enabled: true)
    GitHub.stubs(:multi_tenant_enterprise?).returns(true)
    GitHub::CurrentTenant.stubs(:get).returns(OpenStruct.new(slug: "test-tenant"))

    Timecop.freeze do
      response = assert_difference "DeviceAuthorizationGrant.count", 1 do
        process(integration)
      end

      device_authorization_grant = DeviceAuthorizationGrant.last

      expected = {
        device_code: response[:device_code],
        user_code: device_authorization_grant.user_code,
        verification_uri: "https://test-tenant.github.com/login/device",
        expires_in: device_authorization_grant.expires_in,
        interval: DeviceAuthorizationGrant::INTERVAL
      }

      assert_same_hash expected, response
      hashed_device_code = DeviceAuthorizationGrant.hash_for(response[:device_code])

      assert_equal device_authorization_grant.hashed_device_code, hashed_device_code
      assert_equal device_authorization_grant.device_code_last_eight, response[:device_code].last(8)
    end
  end

  context "special scopes" do
    test "biztools is not grantable", skip_enterprise: true do
      assert_difference "DeviceAuthorizationGrant.count", 1 do
        process(@application, scope: "repo,biztools")
      end

      device_authorization_grant = DeviceAuthorizationGrant.last
      assert_equal ["repo"], device_authorization_grant.scopes
    end

    test "devtools is not grantable", skip_enterprise: true do
      assert_difference "DeviceAuthorizationGrant.count", 1 do
        process(@application, scope: "repo,devtools")
      end

      device_authorization_grant = DeviceAuthorizationGrant.last
      assert_equal ["repo"], device_authorization_grant.scopes
    end

    context "site_admin" do
      test "is not grantable on dotcom", skip_enterprise: true do
        assert_difference "DeviceAuthorizationGrant.count", 1 do
          process(@application, scope: "repo,site_admin")
        end

        device_authorization_grant = DeviceAuthorizationGrant.last
        assert_equal ["repo"], device_authorization_grant.scopes
      end

      test "is grantable on enterprise", enterprise_only: true do
        assert_difference "DeviceAuthorizationGrant.count", 1 do
          process(@application, scope: "repo,site_admin")
        end

        device_authorization_grant = DeviceAuthorizationGrant.last
        assert_same_elements %w[repo site_admin], device_authorization_grant.scopes
      end
    end
  end

  private

  def process(application, params = {}, ip = "1.2.3.4")
    DeviceAuthorizationRequest.process(application, params, ip)
  end
end
