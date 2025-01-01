# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityProductsEnablement
  class SecurityConfigurationSerializerTest < GitHub::TestCase
    include SecurityProductsEnablement::EnterpriseTestHelpers

    fixtures do
      @business = create(:global_business)
      @user = create(:user)
      @org = create(:organization, business: @business, admin: @user)
      @org2 = create(:organization, business: @business, admin: @user)

      @unbundled_org = create(:organization, admin: @user)
      @unbundled_org.set_customer_to_split_metered_offering(actor: @user)

      @team = create(:team, organization: @org, name: "test-team")

      @repo1 = create(:repository, owner: @org)
      @repo2 = create(:repository, owner: @org2)
      @repo3 = create(:repository, owner: @org)
    end

    setup do
      enable_feature_flag(:secret_scanning_generic_secrets_in_security_configurations)

      unless GitHub.enterprise?
        SecretScanning::Features::Owner::ValidityChecks.any_instance.stubs(:feature_available?).returns(true)
      end

      SecretScanning::Features::Org::DelegatedClosures.any_instance.stubs(:feature_available?).returns(true)
      @enterprise_config = create(:security_configuration, :enforced, target: @business)
      @config1 = create(:security_configuration, target: @org)

      create(:repository_security_configuration,
        repository: @repo1,
        security_configuration: @config1,
        state: :attached
      )

      create(:repository_security_configuration,
        repository: @repo2,
        security_configuration: @enterprise_config,
        state: :attached
      )

      create(:repository_security_configuration,
        repository: @repo3,
        security_configuration: @enterprise_config,
        state: :enforced
      )

      @default_for_private = SecurityConfigurationDefault.create!(
        security_configuration: @config1,
        target: @org,
        default_for_new_private_repos: true
      )

      SecurityConfigurationPolicy.create!(
        security_configuration: @config1,
        target: @org,
        enforcement: :not_enforced
      )

      SecurityConfigurationPolicy.create!(
        security_configuration: @enterprise_config,
        target: @org2,
        enforcement: :not_enforced
      )

      if GitHub.enterprise?
        @default_for_public = create(:security_configuration_default, target: @org)
      else
        @default_for_public = SecurityConfigurationDefault.create!(
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
          code_security_sku_enabled: false,
          secret_protection_sku_enabled: false,
          repositories_count: 1
        }
        assert_equal expected, hash
      end

      test "serializes an unbundled configuration" do
        unbundled_config = create(:unbundled_security_configuration, target: @unbundled_org)
        hash = SecurityProductsEnablement::SecurityConfigurationSerializer.new(@unbundled_org).serialize(unbundled_config)

        expected = {
          id: unbundled_config.id,
          name: unbundled_config.name,
          description: unbundled_config.description,
          default_for_new_public_repos: false,
          default_for_new_private_repos: false,
          enforcement: :not_enforced,
          enable_ghas: false,
          code_security_sku_enabled: true,
          secret_protection_sku_enabled: true,
          repositories_count: 0
        }
        assert_equal expected, hash
      end

      test "repositories count returns the number of enforced repositories" do
        hash = SecurityProductsEnablement::SecurityConfigurationSerializer.new(@org2).serialize(@enterprise_config)

        expected = {
          id: @enterprise_config.id,
          name: @enterprise_config.name,
          description: @enterprise_config.description,
          default_for_new_public_repos: false,
          default_for_new_private_repos: false,
          enforcement: :not_enforced,
          enable_ghas: true,
          code_security_sku_enabled: false,
          secret_protection_sku_enabled: false,
          repositories_count: 1
        }
        assert_equal expected, hash
      end

      context "with an enterprise config" do
        test "when rendered by the enterprise, it includes all repos in repositories count" do
          hash = SecurityProductsEnablement::SecurityConfigurationSerializer.new(@business).serialize(@enterprise_config)

          expected = {
            id: @enterprise_config.id,
            name: @enterprise_config.name,
            description: @enterprise_config.description,
            default_for_new_public_repos: false,
            default_for_new_private_repos: false,
            enforcement: :enforced,
            enable_ghas: true,
            code_security_sku_enabled: false,
            secret_protection_sku_enabled: false,
            repositories_count: 2
          }
          assert_equal expected, hash
        end

        test "when rendered by an org, it includes only those repos in that org in the count and the correct enforcement" do
          # For both orgs we expect repositories_count to be 1
          # For org1 we expect enforced, for org2 we expect not_enforced

          hash = SecurityProductsEnablement::SecurityConfigurationSerializer.new(@org).serialize(@enterprise_config)
          expected = {
            id: @enterprise_config.id,
            name: @enterprise_config.name,
            description: @enterprise_config.description,
            default_for_new_public_repos: false,
            default_for_new_private_repos: false,
            enforcement: :enforced,
            enable_ghas: true,
            code_security_sku_enabled: false,
            secret_protection_sku_enabled: false,
            repositories_count: 1
          }
          assert_equal expected, hash

          hash = SecurityProductsEnablement::SecurityConfigurationSerializer.new(@org2).serialize(@enterprise_config)
          expected = {
            id: @enterprise_config.id,
            name: @enterprise_config.name,
            description: @enterprise_config.description,
            default_for_new_public_repos: false,
            default_for_new_private_repos: false,
            enforcement: :not_enforced,
            enable_ghas: true,
            code_security_sku_enabled: false,
            secret_protection_sku_enabled: false,
            repositories_count: 1
          }
          assert_equal expected, hash
        end
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
          code_scanning_delegated_alert_dismissal: "disabled",
          code_scanning_options: { "runner_type" => "not_set", "runner_label" => nil },
          secret_scanning: "enabled",
          secret_scanning_push_protection: "enabled",
          secret_scanning_non_provider_patterns: "disabled",
          secret_scanning_delegated_bypass: "disabled",
          secret_scanning_generic_secrets: "disabled",
          secret_scanning_delegated_alert_dismissal: "disabled",
          enable_ghas: true,
          code_security_sku_enabled: false,
          secret_protection_sku_enabled: false,
          repositories_count: 1
        }

        unless GitHub.enterprise?
          expected[:secret_scanning_validity_checks] = "disabled"
        end

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
          code_security_sku_enabled: false,
          secret_protection_sku_enabled: false,
          repositories_count: 2
        }
        assert_equal expected, hash
      end

      test "serializes the GitHub Recommended Config on an unbundled org", skip_enterprise: true do
        hash = SecurityProductsEnablement::SecurityConfigurationSerializer.new(@unbundled_org).serialize(
          T.must(SecurityConfiguration.github_recommended_configuration)
        )

        expected = {
          id: T.must(SecurityConfiguration.github_recommended_configuration).id,
          name: T.must(SecurityConfiguration.github_recommended_configuration).name,
          description: "Suggested settings for Secret Protection and Code Security, managed by GitHub.",
          default_for_new_public_repos: false,
          default_for_new_private_repos: false,
          enforcement: :not_enforced,
          enable_ghas: false,
          code_security_sku_enabled: true,
          secret_protection_sku_enabled: true,
          repositories_count: 0
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
          code_scanning_delegated_alert_dismissal: "not_set",
          code_scanning_options: { "runner_type" => "not_set", "runner_label" => nil },
          secret_scanning: "enabled",
          secret_scanning_non_provider_patterns: "enabled",
          secret_scanning_validity_checks: "enabled",
          secret_scanning_push_protection: "enabled",
          secret_scanning_delegated_bypass: "not_set",
          secret_scanning_generic_secrets: "not_set",
          secret_scanning_delegated_alert_dismissal: "not_set",
          enable_ghas: true,
          code_security_sku_enabled: false,
          secret_protection_sku_enabled: false,
          repositories_count: 0
        }
        assert_equal expected, hash
      end

      test "serializes the Secret Scanning Push Protection Delegated Bypass reviewers list" do
        team = create(:team, organization: @org, privacy: :closed, name: "delegated-bypass-team")
        config = create(
          :security_configuration,
          target: @org,
          secret_scanning: :enabled,
          secret_scanning_push_protection: :enabled,
          secret_scanning_delegated_bypass: :enabled
        )
        reviewers = [
          SecretScanning::Models::BypassReviewer.new(
            id: 1,
            owner_id: @org.id,
            owner_scope: :ORGANIZATION_SCOPE,
            reviewer_id: team.id,
            reviewer_type: :TEAM
          ),
          SecretScanning::Models::BypassReviewer.new(
            id: 2,
            owner_id: @org.id,
            owner_scope: :ORGANIZATION_SCOPE,
            reviewer_id: T.must(RepositoryRole.admin_role.id),
            reviewer_type: :ROLE
          ),
        ]
        SecretScanning::Services::DelegatedBypassService.expects(:get_bypass_reviewers)
          .with(@org, @user, security_configuration_id: config.id)
          .returns([reviewers, nil])
          .once

        hash = SecurityProductsEnablement::SecurityConfigurationSerializer.new(@org).serialize(config, details: true, actor: @user)

        expected = {
          reviewers: [
            {
              id: 1,
              actorId: team.id,
              actorType: "Team",
              name: team.name,
              bypassMode: 0,
              _enabled: true,
              _dirty: false,
            },
            {
              id: 2,
              actorId: RepositoryRole.admin_role.id,
              actorType: "RepositoryRole",
              name: RepositoryRole.admin_role.name,
              bypassMode: 0,
              _enabled: true,
              _dirty: false,
            }
          ]
        }
        assert_equal config.id, hash[:id]
        assert_equal "enabled", hash[:secret_scanning]
        assert_equal "enabled", hash[:secret_scanning_push_protection]
        assert_equal "enabled", hash[:secret_scanning_delegated_bypass]
        assert_equal expected, hash[:secret_scanning_delegated_bypass_options]
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
          code_security_sku_enabled: false,
          secret_protection_sku_enabled: false,
          repositories_count: 1
        }]
        assert_equal expected, array
      end
    end
  end
end
