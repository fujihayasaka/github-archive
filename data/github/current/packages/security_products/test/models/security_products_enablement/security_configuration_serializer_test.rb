# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityProductsEnablement
  class SecurityConfigurationSerializerTest < GitHub::TestCase
    include SecurityProductsEnablement::EnterpriseTestHelpers

    fixtures do
      business = create(:global_business)
      @user = create(:user)
      @org = create(:organization, business: business, admin: @user)
      @team = create(:team, organization: @org, name: "test-team")

      @repo1 = create(:repository, owner: @org)
    end

    setup do
      GitHub.flipper[:secret_scanning_validity_checks_in_security_configurations].enable

      @config1 = create(:security_configuration, target: @org)
      create(:repository_security_configuration,
        repository: @repo1,
        security_configuration: @config1,
        state: :attached
      )

      SecurityConfigurationDefault.create!(
        security_configuration: @config1,
        target: @org,
        default_for_new_private_repos: true
      )

      SecurityConfigurationPolicy.create!(
        security_configuration: @config1,
        target: @org,
        enforcement: :not_enforced
      )

      unless GitHub.enterprise?
        SecurityConfigurationDefault.create!(
          security_configuration: SecurityConfiguration.github_recommended_configuration,
          target: @org,
          default_for_new_public_repos: true,
        )

        SecurityConfigurationPolicy.create!(
          security_configuration: SecurityConfiguration.github_recommended_configuration,
          target: @org,
          enforcement: :enforced
        )
      end
    end

    context "#serialize" do
      test "serializes a custom configuration" do
        hash = SecurityProductsEnablement::SecurityConfigurationSerializer.new(@org).serialize(@config1)

        expected = {
          id: @config1.id,
          name: @config1.name,
          description: @config1.description,
          default_for_new_public_repos: false,
          default_for_new_private_repos: true,
          enforcement: :not_enforced,
          enable_ghas: true,
          repositories_count: 1
        }
        assert_equal expected, hash
      end

      test "serializes a custom configuration with detail" do
        hash = SecurityProductsEnablement::SecurityConfigurationSerializer.new(@org).serialize(@config1, details: true)

        expected = {
          id: @config1.id,
          name: @config1.name,
          description: @config1.description,
          default_for_new_public_repos: false,
          default_for_new_private_repos: true,
          enforcement: :not_enforced,
          target_type: "User",
          private_vulnerability_reporting: GitHub.enterprise? ? "disabled" : "enabled",
          dependency_graph: "enabled",
          dependency_graph_autosubmit_action: "disabled",
          dependency_graph_autosubmit_action_options: { "labeled_runners" => false },
          dependabot_alerts: "enabled",
          dependabot_security_updates: "enabled",
          code_scanning: "enabled",
          secret_scanning: "enabled",
          secret_scanning_non_provider_patterns: "disabled",
          secret_scanning_push_protection: "enabled",
          secret_scanning_validity_checks: "disabled",
          enable_ghas: true,
          repositories_count: 1
        }
        assert_equal expected, hash
      end

      test "serializes the GitHub Recommended Config", skip_enterprise: true do
        repo = create(:repository, owner: @org)
        create(:repository_security_configuration,
          repository: repo,
          security_configuration: SecurityConfiguration.github_recommended_configuration,
          state: :attached
        )

        repo2 = create(:repository, owner: @org)
        create(:repository_security_configuration,
          repository: repo2,
          security_configuration: SecurityConfiguration.github_recommended_configuration,
          state: :enforced
        )

        hash = SecurityProductsEnablement::SecurityConfigurationSerializer.new(@org).serialize(
          T.must(SecurityConfiguration.github_recommended_configuration)
        )

        expected = {
          id: T.must(SecurityConfiguration.github_recommended_configuration).id,
          name: T.must(SecurityConfiguration.github_recommended_configuration).name,
          description: T.must(SecurityConfiguration.github_recommended_configuration).description,
          default_for_new_public_repos: true,
          default_for_new_private_repos: false,
          enforcement: :enforced,
          enable_ghas: true,
          repositories_count: 2
        }
        assert_equal expected, hash
      end

      test "serializes the GitHub Recommended Config with detail", skip_enterprise: true do
        hash = SecurityProductsEnablement::SecurityConfigurationSerializer.new(@org).serialize(
          T.must(SecurityConfiguration.github_recommended_configuration),
          details: true
        )

        expected = {
          id: T.must(SecurityConfiguration.github_recommended_configuration).id,
          name: T.must(SecurityConfiguration.github_recommended_configuration).name,
          description: T.must(SecurityConfiguration.github_recommended_configuration).description,
          default_for_new_public_repos: true,
          default_for_new_private_repos: false,
          enforcement: :enforced,
          target_type: "global",
          private_vulnerability_reporting: "enabled",
          dependency_graph: "enabled",
          dependency_graph_autosubmit_action: "not_set",
          dependency_graph_autosubmit_action_options: { "labeled_runners" => false },
          dependabot_alerts: "enabled",
          dependabot_security_updates: "not_set",
          code_scanning: "enabled",
          secret_scanning: "enabled",
          secret_scanning_non_provider_patterns: "enabled",
          secret_scanning_validity_checks: "enabled",
          secret_scanning_push_protection: "enabled",
          enable_ghas: true,
          repositories_count: 0
        }
        assert_equal expected, hash
      end
    end

    context "#serialize_collection" do
      test "serializes an array of configurations" do
        array = SecurityProductsEnablement::SecurityConfigurationSerializer.new(@org).serialize_collection([@config1])

        expected = [{
          id: @config1.id,
          name: @config1.name,
          description: @config1.description,
          default_for_new_public_repos: false,
          default_for_new_private_repos: true,
          enforcement: :not_enforced,
          enable_ghas: true,
          repositories_count: 1
        }]
        assert_equal expected, array
      end
    end
  end
end
