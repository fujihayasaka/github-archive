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
    ApplicationRecord::Copilot

  def external_conditional_access_policy_test_enforce
    enforce_result = cap_enforcer.enforce_conditional_access_policies(current_user.enterprise_managed_business, policies: [:external_conditional_access_policy])
    return if enforce_result != :ok
    result = cap_enforcer.evaluate_conditional_access_policies(current_user.enterprise_managed_business, policies: [:external_conditional_access_policy])
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
    TestRoutes.draw do
      get "/external_conditional_access_policy_test_enforce/", to: "external_conditional_access_policy_web_enforcer_test#external_conditional_access_policy_test_enforce"
    end
  end

  setup do
    @tenant_provider = ::OIDC::TenantProvider.new(@business)
    @business.update_ip_allowlist_configuration(actor: @emu, config_value: "idp")
    GitHub.flipper[:idp_cap_for_web_enforcer].enable(@business)
  end

  teardown_once do
    TestRoutes.clear!
  end

  test "return satisfied when ff is enabled and AAD CAP is successful" do
    GitHub.flipper[:idp_cap_for_web].enable(@business)
    as @emu, external_identities: @emu.external_identities.first
    oidc_cap_web(method: :get, url: "external_conditional_access_policy_test_enforce", tenant_id: @tenant_provider.tenant_id, status: :success)
    result = JSON.parse(response.body)["external_conditional_access_policy"]
    assert_equal "satisfied", result
  end

  test "return forbidden when ff is enabled and AAD CAP is unsuccessful" do
    GitHub.flipper[:idp_cap_for_web].enable(@business)
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

  test "return inapplicable when ff is disabled" do
    GitHub.flipper[:idp_cap_for_web].disable(@business)

    as @emu, external_identities: @emu.external_identities.first
    get "external_conditional_access_policy_test_enforce"
    result = JSON.parse(response.body)["external_conditional_access_policy"]
    assert_equal "inapplicable", result
  end
end unless GitHub.single_business_environment?
