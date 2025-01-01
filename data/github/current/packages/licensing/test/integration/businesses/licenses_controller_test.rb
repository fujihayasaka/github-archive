# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessesLicensesControllerHttpTest < GitHub::IntegrationTestCase
  include BusinessTestHelpers
  include TurboghasHelpers

  fixtures do
    @member = create :user
    @owner = create :user
    make_two_factor_credential(@owner)

    @org = create :organization, admins: [@member]
    @business = create :business, owners: [@owner], organizations: [@org]
  end

  setup do
    GitHub::Connect::Authenticator.any_instance.stubs(:license_file_path).returns("#{Rails.root}/test/fixtures/github-enterprise-utf8.ghl")
  end

  context "GET /enterprises/:slug/settings/license" do
    if GitHub.licensed_mode?
      test_business_access do
        get "/enterprises/#{@business.to_param}/settings/license"
      end

      test "shows details of license with unlimited seats" do
        GitHub::Enterprise.license_reset! \
          expire_at: 1.year.from_now.to_datetime, seats: 0, unlimited: true
        as @owner
        get "/enterprises/#{@business.to_param}/settings/license"
        assert_response :success
      end

      test "shows details of license with a set amount of seats" do
        GitHub::Enterprise.license_reset! \
          expire_at: 1.year.from_now.to_datetime, seats: 100, unlimited: false
        as @owner
        get "/enterprises/#{@business.to_param}/settings/license"
        assert_response :success
      end

      test "shows Update license" do
        as @owner
        get "/enterprises/#{@business.to_param}/settings/license"
        assert_response :success
        assert_includes response.body, "Update license"
      end

      test "shows license sync not enabled when not enabled" do
        GitHub.stubs(:dotcom_user_license_usage_upload_enabled?).returns(false)

        as @owner
        get "/enterprises/#{@business.to_param}/settings/license"
        assert_response :success
        assert_includes response.body, "License sync is disabled"
        refute_select "button[type='submit']", text: "Sync now"
      end

      test "shows sync button and license sync pending status before first sync" do
        GitHub.stubs(:dotcom_user_license_usage_upload_enabled?).returns(true)

        as @owner
        get "/enterprises/#{@business.to_param}/settings/license"
        assert_response :success
        assert_select "[data-test-selector='license-sync-status'] .octicon-dot-fill"
        assert_select "[data-test-selector='license-sync-status']", text: /Pending/
        assert_select "button[type='submit']", text: "Sync now"
      end

      test "shows license sync pending status and flash message when clicking button" do
        GitHub.stubs(:dotcom_user_license_usage_upload_enabled?).returns(true)

        as @owner
        post "/enterprises/#{@business.to_param}/settings/license/manual_sync"
        assert_response :redirect
        follow_redirect!
        assert_select "[data-test-selector='flash-container']", text: /Syncing license usage. This may take a few minutes./
        assert_select "[data-test-selector='license-sync-status'] .octicon-dot-fill"
        assert_select "[data-test-selector='license-sync-status']", text: /Pending/
      end

      test "shows license sync success status if sync has succeeded" do
        GitHub.stubs(:dotcom_user_license_usage_upload_enabled?).returns(true)
        DotcomConnection.any_instance.stubs(:license_info_upload_status).returns({ id: "1234", state: "success", updated_at: "2022-01-20T23:14:35Z" })

        as @owner
        get "/enterprises/#{@business.to_param}/settings/license"
        assert_select "[data-test-selector='license-sync-status'] .octicon-check.color-fg-success"
        assert_select "[data-test-selector='license-sync-status']", text: /January 20, 2022 at 23:14:35 UTC/
      end

      test "shows license sync failed status if sync has failed" do
        GitHub.stubs(:dotcom_user_license_usage_upload_enabled?).returns(true)
        DotcomConnection.any_instance.stubs(:license_info_upload_status).returns({ id: "5678", state: "failure", updated_at: "2022-09-30T08:11:56Z" })

        as @owner
        get "/enterprises/#{@business.to_param}/settings/license"
        assert_select "[data-test-selector='license-sync-status'] .octicon-x.color-fg-danger"
        assert_select "[data-test-selector='license-sync-status']", text: /September 30, 2022 at  8:11:56 UTC/
      end

      # The details of the usage display are tested in
      # test/components/advanced_security/business_level_usage_component_test.rb
      test "Advanced Security usage info shown if GHAS enabled" do
        GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(true)

        as @owner
        get "/enterprises/#{@business.to_param}/settings/license"
        assert_response :success
        assert_select("[data-test-selector='business-level-ghas-usage']", count: 1)
      end

      test "Advanced Security usage info not shown if GHAS disabled" do
        GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(false)

        as @owner
        get "/enterprises/#{@business.to_param}/settings/license"
        assert_response :success
        refute_select "[data-test-selector='business-level-ghas-usage']"
      end

      test "Uses provided GHAS org list page number" do
        as @owner
        GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(true)
        get "/enterprises/#{@business.to_param}/settings/license?#{AdvancedSecurityEntitiesLinkRenderer::PAGE_PARAM}=2"

        assert_response :success
        assert_select "div[data-test-selector='ghas-org-list'][data-src='#{settings_business_advanced_security_orgs_list_enterprise_path(page: 2)}']"
      end
    else
      test "returns 404 when not in license mode" do
        as @owner
        get "/enterprises/#{@business.to_param}/settings/license"
        assert_response :not_found
      end
    end
  end

  context "GET /enterprises/:slug/settings/license/download" do
    if GitHub.licensed_mode?
      test_business_access do
        get "/enterprises/#{@business.to_param}/settings/license/download"
      end

      test "downloads license information for admins in JSON format" do
        as @owner

        VCR.use_cassette("get-active-committers", persist_with: :turboghas) do
          get "/enterprises/#{@business.to_param}/settings/license/download"
          assert_response :success
          assert response.headers["Content-Disposition"].start_with?("attachment;")

          data = JSON.parse(response.body)
          assert_equal 1, data["version"]
          refute_nil data["instance"]
          refute_nil data["users"]
        end
      end
    else
      test "returns 404 when not in license mode" do
        as @owner

        get "/enterprises/#{@business.to_param}/settings/license/download"
        assert_response :not_found
      end
    end
  end
end

if GitHub.external_identity_session_enforcement_enabled?
  class BusinessesLicensesControllerActiveExternalIdentitySessionEnforcementHttpTest < GitHub::IntegrationTestCase
    include AuthenticationHelpers::SAML

    fixtures do
      @business = create :business
      @owner = @business.owners.first
    end

    if GitHub.licensed_mode?
      test "is enforced for GET /enterprises/:slug/settings/license" do
        as @owner
        get "/enterprises/#{@business.to_param}/settings/license"
        assert_saml_sso_required
      end
    end
  end
end
