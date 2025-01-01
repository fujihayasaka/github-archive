# typed: true
# frozen_string_literal: true

require "test_helper"
require "oidc/cap_validator"

class ExternalConditionalAccessPolicyWebEnforcerTestController < ApplicationController
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Copilot,
    ApplicationRecord::Repositories

  def external_conditional_access_policy_test_enforce
    enforce_result = cap_enforcer.enforce_conditional_access_policies(current_user.enterprise_managed_business, policies: [:external_conditional_access_policy])
    return if enforce_result != :ok
    result = cap_enforcer.evaluate_conditional_access_policies(current_user.enterprise_managed_business, policies: [:external_conditional_access_policy])
    render json: result
  end

  def external_conditional_access_policy_test_enforce_for_user
    enforce_result = cap_enforcer.enforce_conditional_access_policies(current_user, policies: [:external_conditional_access_policy])
    return if enforce_result != :ok
    result = cap_enforcer.evaluate_conditional_access_policies(current_user, policies: [:external_conditional_access_policy])
    render json: result
  end
end

class ExternalConditionalAccessPolicyWebTest < GitHub::IntegrationTestCase
  include AuthenticationHelpers::OIDC
  skip_enterprise

  fixtures do
    @emu = create :emu, :owner, provider_type: :oidc
    @business = @emu.enterprise_managed_business
  end

  setup_once do
    ::TestRoutes = ActionDispatch::Routing::RouteSet.new unless defined?(::TestRoutes)
    TestRoutes.draw do
      get "/external_conditional_access_policy_test_enforce/", to: "external_conditional_access_policy_web_enforcer_test#external_conditional_access_policy_test_enforce"
      get "/external_conditional_access_policy_test_enforce_for_user/", to: "external_conditional_access_policy_web_enforcer_test#external_conditional_access_policy_test_enforce_for_user"
    end
  end

  setup do
    @tenant_provider = ::OIDC::TenantProvider.new(@business)
    @business.update_ip_allowlist_configuration(actor: @emu, config_value: "idp")
  end

  teardown_once do
    TestRoutes.clear!
  end

  context "web enforcer" do
    test "returns inapplicable when configurable not enabled" do
      @business.disable_idp_ip_allowlist_for_web(actor: @emu)
      refute_predicate @business, :idp_ip_allowlist_for_web_configurable_enabled?

      as @emu, external_identities: @emu.external_identities.first
      get "external_conditional_access_policy_test_enforce"
      result = JSON.parse(response.body)["external_conditional_access_policy"]
      assert_equal "inapplicable", result
    end

    test "returns satisfied when configurable enabled and CAP success" do
      @business.enable_idp_ip_allowlist_for_web(actor: @emu)
      assert_predicate @business, :idp_ip_allowlist_for_web_configurable_enabled?

      as @emu, external_identities: @emu.external_identities.first
      oidc_cap_web(method: :get, url: "external_conditional_access_policy_test_enforce", tenant_id: @tenant_provider.tenant_id, status: :success)

      result = JSON.parse(response.body)["external_conditional_access_policy"]
      assert_equal "satisfied", result
    end

    test "returns forbidden when configurable enabled and CAP failure" do
      @business.enable_idp_ip_allowlist_for_web(actor: @emu)
      assert_predicate @business, :idp_ip_allowlist_for_web_configurable_enabled?

      as @emu, external_identities: @emu.external_identities.first
      oidc_cap_web(method: :get, url: "external_conditional_access_policy_test_enforce", tenant_id: @tenant_provider.tenant_id, status: :failure)

      assert_response :forbidden
      assert_test_selector \
        "external-conditional-access-forbidden-message",
        text: /The #{@business.safe_profile_name} enterprise\s*has enabled Identity Provider Conditional Access Policy enforcement/
      assert_test_selector \
        "external-conditional-access-forbidden-message",
        text: /AADSTS53003:/
    end

    context "other targets passed to interstitial" do
      test "user passed as resource when AAD CAP is unsuccessful shows business name in error" do
        @business.enable_idp_ip_allowlist_for_web(actor: @emu)

        as @emu, external_identities: @emu.external_identities.first
        oidc_cap_web(method: :get, url: "external_conditional_access_policy_test_enforce_for_user", tenant_id: @tenant_provider.tenant_id, status: :failure)
        assert_response :forbidden

        assert_test_selector \
          "external-conditional-access-forbidden-message",
          text: /The #{@business.safe_profile_name} enterprise\s*has enabled Identity Provider Conditional Access Policy enforcement/
        assert_test_selector \
          "external-conditional-access-forbidden-message",
          text: /AADSTS53003:/
      end
    end
  end
end unless GitHub.single_business_environment?
