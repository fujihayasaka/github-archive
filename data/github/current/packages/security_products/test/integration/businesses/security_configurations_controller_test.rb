# typed: true
# frozen_string_literal: true

require "test_helper"

class Business::SecurityAnalysisControllerTest < GitHub::IntegrationTestCase
  include GitHub::ReactPayloadHelper
  include AuditLog::IntegrationTestHelpers
  include SecurityProductsEnablement::EnterpriseTestHelpers
  include TurboghasHelpers

  setup do
    unless GitHub.enterprise?
      SecretScanning::Features::Owner::ValidityChecks.any_instance.stubs(:feature_available?).returns(true)
    end
  end

  EVENTS = %w[
    security_configuration.create
    security_configuration.update
    security_configuration.delete
    security_configuration_policy.update
    security_configuration_default.update
    security_configuration_default.delete
  ]

  fixtures do
    @random_user = create(:user, name: "random-user")
    @owner = create(:user, name: "owner")
    @business = create(:business, owners: [@owner])
    @org = create(:organization, admin: @owner, business: @business)
    @member = create(:user, name: "org-member")
    @org.add_member(@member)
    @security_manager = create(:user, name: "org-security-manager")
    @org.add_member(@security_manager)
    @security_manager_team = create(:security_manager_team, organization: @org)
    @security_manager_team.add_member(@security_manager)

    unless GitHub.enterprise?
      @gh_config = SecurityConfiguration.github_recommended_configuration
    end
  end

  context "#new" do
    test "renders for security managers" do
      as @owner
      get "/enterprises/#{@business.slug}/settings/security_analysis/configurations/new"

      assert_response :success
    end

  end

  context "#create" do
    test "create security configuration without GHAS" do
      assert_difference -> { SecurityConfiguration.count }, 1 do
        as @owner
        post "/enterprises/#{@business.slug}/settings/security_analysis/configurations", params: {
          security_configuration: {
            name: "config name",
            description: "config description",
            enable_ghas: false,
            private_vulnerability_reporting: "disabled",
            dependency_graph: "disabled",
            dependency_graph_autosubmit_action: "disabled",
            dependency_graph_autosubmit_action_options: { "labeled_runners" => false },
            dependabot_alerts: "disabled",
            dependabot_security_updates: "disabled",
            code_scanning: "disabled",
            code_scanning_delegated_alert_dismissal: "disabled",
            secret_scanning: "disabled",
            secret_scanning_non_provider_patterns: "disabled",
            secret_scanning_push_protection: "disabled",
            secret_scanning_delegated_bypass: "disabled",
            secret_scanning_delegated_alert_dismissal: "disabled",
            secret_scanning_generic_secrets: "disabled",
            secret_scanning_validity_checks: "disabled",
          }
        }, as: :json

        assert_response :created
      end

      config = SecurityConfiguration.last!
      assert_equal @business, config.target
      assert_equal "config name", config.name
      assert_equal "config description", config.description
      refute config.enable_ghas?, "expected GHAS to be disabled"
      assert config.code_scanning_disabled?, "expected code scanning to be disabled"
      assert config.code_scanning_delegated_alert_dismissal_disabled?, "expected code scanning delegated alert dismissal to be disabled"
      assert config.secret_scanning_disabled?, "expected secret scanning to be disabled"
      assert config.secret_scanning_push_protection_disabled?, "expected secret scanning push protection to be disabled"
      assert config.secret_scanning_non_provider_patterns_disabled?, "expected secret scanning non provider patterns to be disabled"
      assert config.secret_scanning_delegated_bypass_disabled?, "expected secret scanning delegated bypass to be disabled"
      assert config.secret_scanning_delegated_alert_dismissal_disabled?, "expected secret scanning delegated alert dismissal to be disabled"
      assert config.secret_scanning_validity_checks_disabled?, "expected secret scanning validity checks to be disabled"
    end

    test "returns 201 response when a security configuration is created that excludes ghas but includes other FF'd features" do
      # The test shows that the controller for the enterprise level configuration is robust against mismatches
      # of values for features behind a FF. What might happen is that the front-end logic is not correctly
      # disabling the features that depend on GHAS because the FF is off. The validation logic, however,
      # assumes that those values are set correctly.
      # We currently handle this by filtering the data before trying to create the security configuration.
      # This test exercises that logic. If a better solution for handling this type of mismatch is found
      # we should consider deleting / adapting this test.

      assert_difference -> { SecurityConfiguration.count }, 1 do
        as @owner
        post "/enterprises/#{@business.slug}/settings/security_analysis/configurations", params: {
          security_configuration: {
            name: "config name",
            description: "config description",
            enable_ghas: false,
            private_vulnerability_reporting: "disabled",
            dependency_graph: "disabled",
            dependency_graph_autosubmit_action: "disabled",
            dependency_graph_autosubmit_action_options: { "labeled_runners" => false },
            dependabot_alerts: "disabled",
            dependabot_security_updates: "disabled",
            code_scanning: "disabled",
            code_scanning_delegated_alert_dismissal: "disabled",
            secret_scanning: "disabled",
            secret_scanning_non_provider_patterns: "disabled",
            secret_scanning_push_protection: "disabled",
            secret_scanning_delegated_bypass: "disabled",
            secret_scanning_delegated_alert_dismissal: "disabled",
            secret_scanning_generic_secrets: "disabled",
            secret_scanning_validity_checks: "disabled",
          }
        }, as: :json

        assert_response :created
      end

      config = SecurityConfiguration.last!
      assert_equal @business, config.target
      refute config.enable_ghas?, "expected GHAS to be enabled"
      assert config.code_scanning_delegated_alert_dismissal_disabled?
    end

  end

end
