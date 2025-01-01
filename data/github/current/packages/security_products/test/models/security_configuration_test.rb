# typed: true
# frozen_string_literal: true

require "test_helper"

class SecurityConfigurationTest < GitHub::TestCase
  include SecurityProductsEnablement::EnterpriseTestHelpers
  fixtures do
    @org = create(:organization)
    @user = create(:user)
    @business = create(:business, owners: [@user], organizations: [@org])

    @model_hash = {
      "name" => "config name",
      "description" => "config description",
      "enable_ghas" => true,
      "private_vulnerability_reporting" => "disabled",
      "dependency_graph" => "enabled",
      "dependency_graph_autosubmit_action" => "disabled",
      "dependency_graph_autosubmit_action_options" => {},
      "dependabot_alerts" => "enabled",
      "dependabot_security_updates" => "not_set",
      "code_scanning" => "enabled",
      "code_scanning_delegated_alert_dismissal" => "not_set",
      "secret_scanning" => "enabled",
      "secret_scanning_push_protection" => "enabled",
      "secret_scanning_delegated_bypass" => "not_set",
      "secret_scanning_delegated_alert_dismissal" => "not_set",
      "target" => @org
    }.freeze
  end

  context ".create_configuration" do
    test "can create a security configuration without setting it as a default for new repos" do
      config = SecurityConfiguration.create_configuration(
        model_hash: @model_hash,
        default_for_new_public_repos: false,
        default_for_new_private_repos: false,
        enforcement: :not_enforced,
        actor: @user
      )

      assert config.persisted?
      assert_equal @org, config.target
      assert_equal "config name", config.name
      assert_equal "config description", config.description
      assert config.enable_ghas?, "expected GHAS to be enabled"
      assert config.private_vulnerability_reporting_disabled?, "expected PVR to be disabled"
      assert config.dependency_graph_enabled?, "expected dependency graph to be enabled"
      assert config.dependency_graph_autosubmit_action_disabled?, "expected dg autosubmit to be not set"
      assert config.dependabot_alerts_enabled?, "expected dependabot alerts to be enabled"
      assert config.dependabot_security_updates_not_set?, "expected dependabot security updates to be not set"
      assert config.code_scanning_enabled?, "expected code scanning to be enabled"
      assert config.code_scanning_delegated_alert_dismissal_not_set?, "expected code scanning delegated alert dismissal to be not set"
      assert config.secret_scanning_enabled?, "expected secret scanning to be enabled"
      assert config.secret_scanning_push_protection_enabled?, "expected secret scanning push protection to be enabled"
      assert config.secret_scanning_delegated_alert_dismissal_not_set?, "expected secret scanning delegated alert dismissal to be not set"

      assert_equal config.dependency_graph_autosubmit_action_options,
                   { "labeled_runners" => false },
                   "expected default options for dg autosubmit to be persisted"

      assert_equal 0, config.security_configuration_defaults.count
    end

    test "can create a security configuration and set it as default for new public repos" do
      config = SecurityConfiguration.create_configuration(
        model_hash: @model_hash,
        default_for_new_public_repos: true,
        default_for_new_private_repos: false,
        enforcement: :not_enforced,
        actor: @user
      )

      assert config.persisted?
      assert_equal @org, config.target

      assert_equal 1, config.security_configuration_defaults.where(default_for_new_public_repos: true).count
    end

    test "can create a security configuration and set it as default for new private and internal repos" do
      config = SecurityConfiguration.create_configuration(
        model_hash: @model_hash,
        default_for_new_public_repos: false,
        default_for_new_private_repos: true,
        enforcement: :not_enforced,
        actor: @user
      )

      assert config.persisted?
      assert_equal @org, config.target

      assert_equal 1, config.security_configuration_defaults.where(default_for_new_private_repos: true).count
    end

    test "can create a security configuration and set it as enforced" do
      config = SecurityConfiguration.create_configuration(
        model_hash: @model_hash,
        default_for_new_public_repos: false,
        default_for_new_private_repos: true,
        enforcement: :enforced,
        actor: @user
      )

      assert config.persisted?
      assert_equal @org, config.target

      assert_equal 1, config.security_configuration_policies.enforced.count
    end

    test "exits early when the configuration is invalid" do
      attributes = @model_hash.merge("name" => "GitHub recommended")

      assert_no_changes("SecurityConfigurationDefault.count") do
        config = SecurityConfiguration.create_configuration(
          model_hash: attributes,
          default_for_new_public_repos: true,
          default_for_new_private_repos: true,
          enforcement: :not_enforced,
          actor: @user
        )
        refute config.persisted?
      end
    end

    test "secret scanning delegated bypass reviewers are created if present when the configuration is created" do
      options = {
        secret_scanning_delegated_bypass: {
          reviewers: [
            {
              "actorId" => 1,
              "actorType" => "RepositoryRole",
            }
          ]
        }
      }
      model_hash = {
        "name" => "config name",
        "description" => "config description",
        "enable_ghas" => true,
        "private_vulnerability_reporting" => "disabled",
        "dependency_graph" => "enabled",
        "dependency_graph_autosubmit_action" => "disabled",
        "dependency_graph_autosubmit_action_options" => {},
        "dependabot_alerts" => "enabled",
        "dependabot_security_updates" => "not_set",
        "code_scanning" => "enabled",
        "code_scanning_delegated_alert_dismissal" => "not_set",
        "secret_scanning" => "enabled",
        "secret_scanning_push_protection" => "enabled",
        "secret_scanning_delegated_bypass" => "enabled",
        "target" => @org
      }

      SecretScanning::Services::DelegatedBypassService.expects(:update_bypass_reviewers_for_source).once
      SecretScanning::Services::DelegatedBypassService.expects(:remove_bypass_reviewers_for_source).never

      config = SecurityConfiguration.create_configuration(
        model_hash: model_hash,
        default_for_new_public_repos: false,
        default_for_new_private_repos: false,
        enforcement: :not_enforced,
        actor: @user,
        options:
      )

      assert config.persisted?
      assert_equal @org, config.target
    end

    context "feature options" do
      test "only defined options are persisted" do
        model_hash = {
          "name" => "config name",
          "description" => "config description",
          "enable_ghas" => true,
          "private_vulnerability_reporting" => "disabled",
          "dependency_graph" => "enabled",
          "dependency_graph_autosubmit_action" => "disabled",
          "dependency_graph_autosubmit_action_options" => {
            "labeled_runners" => false,
            "random_other" => "shouldn't be here"
          },
          "dependabot_alerts" => "enabled",
          "dependabot_security_updates" => "not_set",
          "code_scanning" => "enabled",
          "code_scanning_delegated_alert_dismissal" => "not_set",
          "secret_scanning" => "enabled",
          "secret_scanning_push_protection" => "enabled",
          "secret_scanning_delegated_bypass" => "not_set",
          "target" => @org
        }

        config = SecurityConfiguration.create_configuration(
          model_hash: model_hash,
          default_for_new_public_repos: false,
          default_for_new_private_repos: false,
          enforcement: :not_enforced,
          actor: @user
        )

        assert config.persisted?

        expected_options = { "labeled_runners" => false }
        assert_equal expected_options, config.dependency_graph_autosubmit_action_options
      end
    end
  end

  context "#update_configuration" do
    test "updates a security configuration without setting it as a default for new repos" do
      config = create(:security_configuration, target: @org)
      model_hash = {
        "name" => "config name",
        "description" => "config description",
        "enable_ghas" => true,
        "private_vulnerability_reporting" => "disabled",
        "dependency_graph" => "disabled",
        "dependency_graph_autosubmit_action" => "enabled",
        "dependency_graph_autosubmit_action_options" => { "labeled_runners" => true },
        "dependabot_alerts" => "disabled",
        "dependabot_security_updates" => "disabled",
        "code_scanning" => "enabled",
        "code_scanning_delegated_alert_dismissal" => "not_set",
        "secret_scanning" => "not_set",
        "secret_scanning_push_protection" => "not_set",
        "target" => @org
      }

      config.update_configuration(model_hash, @org.owner, type: :organization)

      assert_equal @org, config.target
      assert_equal "config name", config.name
      assert_equal "config description", config.description
      assert config.enable_ghas?, "expected GHAS to be enabled"
      assert config.private_vulnerability_reporting_disabled?, "expected PVR to be disabled"
      assert config.dependency_graph_disabled?, "expected dependency graph to be disabled"
      assert config.dependabot_alerts_disabled?, "expected dependabot alerts to be disabled"
      assert config.dependabot_security_updates_disabled?, "expected dependabot security updates to be disabled"
      assert config.dependency_graph_autosubmit_action_enabled?, "expected dg autosubmit to be enabled"
      assert config.code_scanning_enabled?, "expected code scanning to be enabled"
      assert config.code_scanning_delegated_alert_dismissal_not_set?, "expected code scanning delegated alert dismissal to be not set"
      assert config.secret_scanning_not_set?, "expected secret scanning to be not set"
      assert config.secret_scanning_push_protection_not_set?, "expected secret scanning push protection to be not set"

      assert_equal config.dependency_graph_autosubmit_action_options,
                   { "labeled_runners" => true },
                   "expected option values for dg autosubmit actions to be persisted"

      assert_equal 0, config.security_configuration_defaults.count
    end

    test "sets a configuration as default for new public repos" do
      config = create(:security_configuration, target: @org)
      model_hash = {
        "name" => config.name,
        "description" => config.description,
        "enable_ghas" => true,
        "private_vulnerability_reporting" => GitHub.enterprise? ? "disabled" : "enabled",
        "dependency_graph" => "enabled",
        "dependency_graph_autosubmit_action" => "disabled",
        "dependabot_alerts" => "enabled",
        "dependabot_security_updates" => "enabled",
        "code_scanning" => "enabled",
        "code_scanning_delegated_alert_dismissal" => "disabled",
        "secret_scanning" => "enabled",
        "secret_scanning_push_protection" => "enabled",
        "target" => @org
      }

      config.update_configuration(model_hash, @org.owner, type: :organization, default_for_new_public_repos: true, default_for_new_private_repos: false)

      assert_equal 1, config.security_configuration_defaults.where(default_for_new_public_repos: true).count
    end

    test "sets a configuration as default for new private and internal repos" do
      config = create(:security_configuration, target: @org)
      model_hash = {
        "name" => config.name,
        "description" => config.description,
        "enable_ghas" => true,
        "private_vulnerability_reporting" => GitHub.enterprise? ? "disabled" : "enabled",
        "dependency_graph" => "enabled",
        "dependency_graph_autosubmit_action" => "disabled",
        "dependabot_alerts" => "enabled",
        "dependabot_security_updates" => "enabled",
        "code_scanning" => "enabled",
        "code_scanning_delegated_alert_dismissal" => "disabled",
        "secret_scanning" => "enabled",
        "secret_scanning_push_protection" => "enabled",
        "target" => @org
      }

      config.update_configuration(model_hash, @org.owner, type: :organization, default_for_new_public_repos: false, default_for_new_private_repos: true)

      assert_equal 1, config.security_configuration_defaults.where(default_for_new_private_repos: true).count
    end

    test "sets a configuration as enforced" do
      config = create(:security_configuration, target: @org)
      model_hash = {
        "name" => config.name,
        "description" => config.description,
        "enable_ghas" => true,
        "private_vulnerability_reporting" => GitHub.enterprise? ? "disabled" : "enabled",
        "dependency_graph" => "enabled",
        "dependency_graph_autosubmit_action" => "disabled",
        "dependabot_alerts" => "enabled",
        "dependabot_security_updates" => "enabled",
        "code_scanning" => "enabled",
        "code_scanning_delegated_alert_dismissal" => "disabled",
        "secret_scanning" => "enabled",
        "secret_scanning_push_protection" => "enabled",
        "target" => @org
      }

      config.update_configuration(model_hash, @org.owner, type: :organization, default_for_new_public_repos: false, default_for_new_private_repos: false, enforcement: :enforced)

      assert_equal 1, config.security_configuration_policies.enforced.count
    end

    test "sets a configuration as not enforced" do
      config = create(:security_configuration, target: @org)
      model_hash = {
        "name" => config.name,
        "description" => config.description,
        "enable_ghas" => true,
        "private_vulnerability_reporting" => GitHub.enterprise? ? "disabled" : "enabled",
        "dependency_graph" => "enabled",
        "dependency_graph_autosubmit_action" => "disabled",
        "dependabot_alerts" => "enabled",
        "dependabot_security_updates" => "enabled",
        "code_scanning" => "enabled",
        "code_scanning_delegated_alert_dismissal" => "disabled",
        "secret_scanning" => "enabled",
        "secret_scanning_push_protection" => "enabled",
        "target" => @org
      }

      config.update_configuration(model_hash, @org.owner, type: :organization, default_for_new_public_repos: false, default_for_new_private_repos: false, enforcement: :not_enforced)

      assert_equal 1, config.security_configuration_policies.not_enforced.count
    end

    test "exits early when the configuration is invalid" do
      config = create(:security_configuration, target: @org)
      model_hash = {
        "name" => "GitHub recommended",
        "description" => config.description,
        "enable_ghas" => true,
        "private_vulnerability_reporting" => GitHub.enterprise? ? "disabled" : "enabled",
        "dependency_graph" => "enabled",
        "dependency_graph_autosubmit_action" => "disabled",
        "dependabot_alerts" => "enabled",
        "dependabot_security_updates" => "enabled",
        "code_scanning" => "enabled",
        "code_scanning_delegated_alert_dismissal" => "disabled",
        "secret_scanning" => "enabled",
        "secret_scanning_push_protection" => "enabled",
        "target" => @org
      }

      assert_no_changes("SecurityConfigurationDefault.count") do
        assert_no_enqueued_jobs do
          config.update_configuration(model_hash, @org.owner, type: :organization, default_for_new_public_repos: false, default_for_new_private_repos: true)
        end
      end
    end

    test "enqueues jobs to update the security configuration for all attached repos when features are toggled for org config" do
      repo = create(:repository, :minimal, owner: @org)
      config = create(
        :security_configuration,
        target: @org,
        dependency_graph: "disabled",
        dependabot_alerts: "disabled",
        dependabot_security_updates: "disabled"
      )
      create(
        :repository_security_configuration,
        security_configuration: config,
        repository: repo,
        state: "attached",
      )
      model_hash = {
        "dependency_graph" => "enabled",
        "dependabot_alerts" => "enabled",
        "target" => @org
      }

      assert_enqueued_with(
        job: SecurityProductsEnablement::OrganizationSecurityConfigurationJob,
        args: [{ actor_id: @org.owner.id, organization_id: @org.id, security_configuration_id: config.id, action: :update, repository_ids: nil, options: {} }]
      ) do
        config.update_configuration(model_hash, @org.owner, type: :organization)
      end
    end

    test "enqueues jobs to update the security configuration for all attached repos when features are toggled for enterprise config" do
      repo = create(:repository, :minimal, owner: @org)
      config = create(
        :security_configuration,
        target: @business,
        dependency_graph: "disabled",
        dependabot_alerts: "disabled",
        dependabot_security_updates: "disabled"
      )
      create(
        :repository_security_configuration,
        security_configuration: config,
        repository: repo,
        state: "attached",
      )
      model_hash = {
        "dependency_graph" => "enabled",
        "dependabot_alerts" => "enabled",
        "target" => @business
      }

      assert_enqueued_with(
        job: SecurityProductsEnablement::EnterpriseSecurityConfigurationJob,
        args: [{ actor_id: @user.id, enterprise_id: @business.id, security_configuration_id: config.id, action: :update, options: {} }]
      ) do
        config.update_configuration(model_hash, @user, type: :enterprise)
      end
    end

    test "enqueues job to update the security configuration for all attached repos when secret scanning is enabled for org config" do
      %w(disabled not_set).each do |status|
        repo = create(:repository, :minimal, owner: @org)
        security_config = create(
          :security_configuration,
          target: @org,
          secret_scanning: status,
          secret_scanning_push_protection: status,
          secret_scanning_delegated_bypass: status,
          secret_scanning_validity_checks: GitHub.secret_scanning_validity_checks_available_on_instance? ? status : :disabled,
          secret_scanning_non_provider_patterns: status,
        )
        create(
          :repository_security_configuration,
          security_configuration: security_config,
          repository: repo,
          state: "attached",
        )
        model_hash = {
          "secret_scanning" => "enabled",
          "target" => @org
        }

        assert_enqueued_with(
          job: SecurityProductsEnablement::OrganizationSecurityConfigurationJob,
          args: [{
            actor_id: @org.owner.id, organization_id: @org.id,
            security_configuration_id: security_config.id, action: :update,
            repository_ids: nil, options: { publish_backfill_group_request: true }
          }]
        ) do
          security_config.update_configuration(model_hash, @org.owner, type: :organization)
        end
      end
    end

    test "enqueues job to update the security configuration for all attached repos when secret scanning is enabled for enterprise config" do
      %w(disabled not_set).each do |status|
        repo = create(:repository, :minimal, owner: @org)
        security_config = create(
          :security_configuration,
          target: @business,
          secret_scanning: status,
          secret_scanning_push_protection: status,
          secret_scanning_validity_checks: GitHub.secret_scanning_validity_checks_available_on_instance? ? status : "disabled",
          secret_scanning_non_provider_patterns: status,
        )
        create(
          :repository_security_configuration,
          security_configuration: security_config,
          repository: repo,
          state: "attached",
        )
        model_hash = {
          "secret_scanning" => "enabled",
          "target" => @business
        }

        assert_enqueued_with(
          job: SecurityProductsEnablement::EnterpriseSecurityConfigurationJob,
          args: [{
            actor_id: @user.id, enterprise_id: @business.id,
            security_configuration_id: security_config.id, action: :update,
            options: { publish_backfill_group_request: true }
          }]
        ) do
          security_config.update_configuration(model_hash, @user, type: :enterprise)
        end
      end
    end

    test "does not enqueue jobs to update attached repos when only the name or description is changed" do
      repo = create(:repository, :minimal, owner: @org)
      config = create(:security_configuration, target: @org)
      create(
        :repository_security_configuration,
        security_configuration: config,
        repository: repo,
        state: "attached"
      )
      model_hash = {
        "name" => "a different config name",
        "description" => "a different config description",
        "target" => @org
      }

      assert_no_enqueued_jobs(only: SecurityProductsEnablement::OrganizationSecurityConfigurationJob) do
        config.update_configuration(model_hash, @org.owner, type: :organization)
      end
    end

    test "enqueues jobs to update the security configuration for all attached repos when enforcement is toggled for org config" do
      repo = create(:repository, :minimal, owner: @org)
      config = create(
        :security_configuration,
        target: @org,
        dependency_graph: "disabled",
        dependabot_alerts: "disabled",
        dependabot_security_updates: "disabled"
      )
      create(
        :repository_security_configuration,
        security_configuration: config,
        repository: repo,
        state: "attached",
      )

      model_hash = {
        "target" => @org,
      }

      assert_enqueued_with(
        job: SecurityProductsEnablement::OrganizationSecurityConfigurationJob,
        args: [{ actor_id: @org.owner.id, organization_id: @org.id, security_configuration_id: config.id, action: :update, repository_ids: nil, options: {} }]
      ) do
        config.update_configuration(model_hash, @org.owner, type: :organization, enforcement: :enforced)
      end
    end

    test "enqueues jobs to update the security configuration for all attached repos when enforcement is toggled for enterprise config" do
      repo = create(:repository, :minimal, owner: @org)
      config = create(
        :security_configuration,
        target: @business,
        dependency_graph: "disabled",
        dependabot_alerts: "disabled",
        dependabot_security_updates: "disabled"
      )
      create(
        :repository_security_configuration,
        security_configuration: config,
        repository: repo,
        state: "attached",
      )

      model_hash = {
        "target" => @business,
      }

      assert_enqueued_with(
        job: SecurityProductsEnablement::EnterpriseSecurityConfigurationJob,
        args: [{ actor_id: @user.id, enterprise_id: @business.id, security_configuration_id: config.id, action: :update, options: {} }]
      ) do
        config.update_configuration(model_hash, @user, type: :enterprise, enforcement: :enforced)
      end
    end

    test "enqueues jobs to update all repos in a single org that are attached to the GH config when enforcement is toggled for org config", skip_enterprise: true do
      repo = create(:repository, :minimal, organization: @org)
      config = T.must(SecurityConfiguration.github_recommended_configuration)
      create(
        :repository_security_configuration,
        security_configuration: config,
        repository: repo,
        user: @org,
        state: "attached",
      )
      model_hash = { "target" => @org }

      assert_enqueued_with(
        job: SecurityProductsEnablement::OrganizationSecurityConfigurationJob,
        args: [{ actor_id: @org.owner.id, organization_id: @org.id, security_configuration_id: T.must(config).id, action: :update, repository_ids: nil, options: {} }]
      ) do
        config.update_configuration(model_hash, @org.owner, type: :organization, enforcement: :enforced)
      end
    end

    test "enqueues jobs to update all repos attached to the GH config when enforcement is toggled for enterprise config", skip_enterprise: true do
      repo = create(:repository, :minimal, organization: @org)
      config = T.must(SecurityConfiguration.github_recommended_configuration)
      create(
        :repository_security_configuration,
        security_configuration: config,
        repository: repo,
        user: @org,
        state: "attached",
      )
      model_hash = { "target" => @business }

      assert_enqueued_with(
        job: SecurityProductsEnablement::EnterpriseSecurityConfigurationJob,
        args: [{ actor_id: @user.id, enterprise_id: @business.id, security_configuration_id: config.id, action: :update, options: {} }]
      ) do
        config.update_configuration(model_hash, @user,  type: :enterprise, enforcement: :enforced)
      end
    end

    test "does not update the settings of the GH config", skip_enterprise: true do
      repo = create(:repository, :minimal, organization: @org)
      config = T.must(SecurityConfiguration.github_recommended_configuration)
      model_hash = {
        "name" => "GH config is mine now",
        "description" => T.must(config).description,
        "enable_ghas" => false,
        "private_vulnerability_reporting" => "disabled",
        "dependency_graph" => "disabled",
        "dependency_graph_autosubmit_action" => "disabled",
        "dependabot_alerts" => "disabled",
        "dependabot_security_updates" => "disabled",
        "code_scanning" => "disabled",
        "code_scanning_delegated_alert_dismissal" => "disabled",
        "secret_scanning" => "disabled",
        "secret_scanning_push_protection" => "disabled",
        "target" => @org,
      }

      assert_no_changes -> { T.must(config).attributes.except("created_at", "updated_at") } do
        config.update_configuration(model_hash, @org.owner, type: :organization)
      end
    end

    test "secret scanning delegated bypass reviewers are updated if present and enabled" do
      config = create(:security_configuration, target: @org)
      reviewers = [
        {
          owner_id: @org.id,
          owner_scope: :ORGANIZATION_SCOPE,
          security_configuration_id: config.id,
          reviewer_id: 1,
          reviewer_type: :ROLE,
        }
      ]
      options = {
        secret_scanning_delegated_bypass: {
          reviewers: [
            {
              "actorId" => 1,
              "actorType" => "RepositoryRole",
            }
          ]
        }
      }
      model_hash = {
        "name" => "config name",
        "description" => "config description",
        "enable_ghas" => true,
        "private_vulnerability_reporting" => "disabled",
        "dependency_graph" => "enabled",
        "dependency_graph_autosubmit_action" => "disabled",
        "dependency_graph_autosubmit_action_options" => {},
        "dependabot_alerts" => "enabled",
        "dependabot_security_updates" => "not_set",
        "code_scanning" => "enabled",
        "code_scanning_delegated_alert_dismissal" => "not_set",
        "secret_scanning" => "enabled",
        "secret_scanning_push_protection" => "enabled",
        "secret_scanning_delegated_bypass" => "enabled",
        "target" => @org
      }

      SecretScanning::Services::DelegatedBypassService.expects(:remove_bypass_reviewers_for_source).never
      SecretScanning::Services::DelegatedBypassService.expects(:update_bypass_reviewers_for_source).once
        .with(@org, config.id, reviewers, @org.owner)
        .returns([reviewers, nil])

      config.update_configuration(model_hash, @org.owner, type: :organization, options: options)

      assert_equal @org, config.target
    end

    test "secret scanning delegated bypass reviewers are deleted if toggled disabled" do
      config = create(:security_configuration, target: @org, secret_scanning_delegated_bypass: "enabled")
      model_hash = {
        "name" => "config name",
        "description" => "config description",
        "enable_ghas" => true,
        "private_vulnerability_reporting" => "disabled",
        "dependency_graph" => "enabled",
        "dependency_graph_autosubmit_action" => "disabled",
        "dependency_graph_autosubmit_action_options" => {},
        "dependabot_alerts" => "enabled",
        "dependabot_security_updates" => "not_set",
        "code_scanning" => "enabled",
        "code_scanning_delegated_alert_dismissal" => "not_set",
        "secret_scanning" => "enabled",
        "secret_scanning_push_protection" => "enabled",
        "secret_scanning_delegated_bypass" => "disabled",
        "target" => @org
      }

      SecretScanning::Services::DelegatedBypassService.expects(:update_bypass_reviewers_for_source).never
      SecretScanning::Services::DelegatedBypassService.expects(:remove_bypass_reviewers_for_source).once
        .with(@org, config.id, @org.owner)
        .returns(nil)

      config.update_configuration(model_hash, @org.owner, type: :organization)

      assert_equal @org, config.target
    end

    test "secret scanning delegated bypass reviewers are ignored if remaining disabled" do
      config = create(:security_configuration, target: @org)
      model_hash = {
        "name" => "config name",
        "description" => "config description",
        "enable_ghas" => true,
        "private_vulnerability_reporting" => "disabled",
        "dependency_graph" => "enabled",
        "dependency_graph_autosubmit_action" => "disabled",
        "dependency_graph_autosubmit_action_options" => {},
        "dependabot_alerts" => "enabled",
        "dependabot_security_updates" => "not_set",
        "code_scanning" => "enabled",
        "code_scanning_delegated_alert_dismissal" => "not_set",
        "secret_scanning" => "enabled",
        "secret_scanning_push_protection" => "enabled",
        "secret_scanning_delegated_bypass" => "disabled",
        "target" => @org
      }

      SecretScanning::Services::DelegatedBypassService.expects(:remove_bypass_reviewers_for_source).never
      SecretScanning::Services::DelegatedBypassService.expects(:update_bypass_reviewers_for_source).never

      config.update_configuration(model_hash, @org.owner, type: :organization)

      assert_equal @org, config.target
    end
  end

  context "#delete_configuration" do
    test "secret scanning delegated bypass reviewers are deleted if configuration is deleted and was enabled" do
      config = create(:security_configuration, target: @org, secret_scanning_delegated_bypass: "enabled")
      SecretScanning::Services::DelegatedBypassService.expects(:update_bypass_reviewers_for_source).never
      SecretScanning::Services::DelegatedBypassService.expects(:remove_bypass_reviewers_for_source).once
        .with(@org, config.id, @org.owner)
        .returns(nil)

      config.delete_configuration(@org.owner)
    end

    test "secret scanning delegated bypass reviewers are ignored if configuration is deleted and was disabled" do
      config = create(:security_configuration, target: @org, secret_scanning_delegated_bypass: "disabled")
      SecretScanning::Services::DelegatedBypassService.expects(:remove_bypass_reviewers_for_source).never
      SecretScanning::Services::DelegatedBypassService.expects(:update_bypass_reviewers_for_source).never

      config.delete_configuration(@org.owner)
    end
  end

  context "validations" do
    test "given fields should be present for record to be valid" do
      # Add description here
      required_fields = {
        name: "config name",
        enable_ghas: true,
        dependency_graph: 1,
        dependabot_alerts: 1,
        dependabot_security_updates: 1,
        code_scanning: 1,
        code_scanning_delegated_alert_dismissal: 1,
        secret_scanning: 1,
        secret_scanning_push_protection: 1,
      }

      unless GitHub.enterprise?
        required_fields[:private_vulnerability_reporting] = 1
      end

      security_config = build(:security_configuration, required_fields)
      assert security_config.valid?

      required_fields.each do |field, _value|
        security_config.update("#{field}": nil)
        refute security_config.valid?
      end
    end

    test "name is required to be 100 characters or less" do
      valid_names = ["a" * 100, GRIN_EMOJI * 100]
      invalid_names = valid_names.map { |name| name + "x" }

      valid_names.each do |valid_name|
        security_config = build(:security_configuration, name: valid_name)
        assert_predicate security_config, :valid?

        security_config.save!
        assert_equal valid_name, security_config.class.find(security_config.id).name
      end

      invalid_names.each do |invalid_name|
        refute_predicate build(:security_configuration, name: invalid_name), :valid?
      end
    end

    test "name should not be in the reserved names list" do
      SecurityConfigurationValidator::RESERVED_NAMES.each do |name|
        security_config = build(:security_configuration, name: name)
        refute security_config.valid?

        # Add whitespace around the reserved name
        security_config = build(:security_configuration, name: " #{name} ")
        refute security_config.valid?
      end
    end

    test "name should be unique for a given organization" do
      config1 = create(:security_configuration, {
        name: "Custom config for DXP org",
        target: @org,
      })

      config2 = create(:security_configuration, {
        name: "Enable dependabot only for DXP org",
        target: @org,
      })

      # Updating an existing config's name to another config's name should be invalid
      refute config2.update(name: config1.name)
      assert_equal "Name has already been taken", config2.errors.full_messages.first

      config3 = build(:security_configuration, {
        name: config1.name,
        target: @org,
      })

      # Creating a config with an existing config's name should be invalid
      refute config3.valid?
      assert_equal "Name has already been taken", config3.errors.full_messages.first
    end

    test "name should be unique across enterprise and organization" do
      config1 = create(:security_configuration, {
        name: "Custom config",
        target: @org,
      })

      config2 = build(:security_configuration, {
        name: config1.name,
        target: @business,
      })

      # Creating an enterprise config with an org config's name should be invalid
      refute config2.valid?
      assert_equal "Name has already been taken by an organization in enterprise", config2.errors.full_messages.first

      config3 = create(:security_configuration, {
        name: "Another custom config",
        target: @business,
      })

      # Updating an existing enterprise config's name to an org config's name should be invalid
      refute config3.update(name: config1.name)
      assert_equal "Name has already been taken by an organization in enterprise", config3.errors.full_messages.first

      config4 = build(:security_configuration, {
        name: config3.reload.name,
        target: @org,
      })

      # Creating a org config with an enterprise config's name should be invalid
      refute config4.valid?
      assert_equal "Name has already been taken by an enterprise configuration", config4.errors.full_messages.first
    end

    test "description should not exceed 255 characters" do
      description = "security_config_description" * 50

      security_config = build(:security_configuration, description: description)
      refute security_config.valid?
    end

    test "dependabot alerts can only be enabled if dependency graph is enabled" do
      required_fields = {
        dependabot_alerts: 1,
        dependency_graph: 0
      }

      config = build(:security_configuration, required_fields)
      refute config.valid?

      required_fields["dependency_graph"] = 1
      config = build(:security_configuration, required_fields)
      assert config.valid?
    end

    test "automatic dependency submission can only be enabled if dependency graph is enabled", skip_enterprise: true do
      required_fields = {
        dependency_graph: 0,
        dependency_graph_autosubmit_action: 1,
        # All other DG dependants are disabled
        dependabot_alerts: 0,
        dependabot_security_updates: 0,
      }

      config = build(:security_configuration, required_fields)
      refute config.valid?

      required_fields["dependency_graph"] = 1
      config = build(:security_configuration, required_fields)
      assert config.valid?
    end

    test "dependabot security updates can only be enabled if dependabot alerts is enabled" do
      required_fields = {
        dependabot_security_updates: 1,
        dependabot_alerts: 0,
      }

      config = build(:security_configuration, required_fields)
      refute config.valid?

      required_fields["dependabot_alerts"] = 1
      config = build(:security_configuration, required_fields)
      assert config.valid?
    end

    test "push protection can only be enabled if secret scanning is enabled" do
      required_fields = {
        secret_scanning_push_protection: 1,
        secret_scanning: 0,
      }

      config = build(:security_configuration, required_fields)
      refute config.valid?

      required_fields["secret_scanning"] = 1
      config = build(:security_configuration, required_fields)
      assert config.valid?
    end

    test "ghas features can only be enabled if enable_ghas is true" do
      SecurityConfiguration::GHAS_FEATURES.each do |feature|
        required_fields = {
          "#{feature}": 1,
          enable_ghas: false,
        }

        config = build(:security_configuration, required_fields)
        refute config.valid?

        required_fields["enable_ghas"] = true
        config = build(:security_configuration, required_fields)
        assert config.valid? unless feature == :secret_scanning_validity_checks && !GitHub.secret_scanning_validity_checks_available_on_instance?
      end
    end

    test "prohibits use of code_security_sku_enabled" do
      config = build(:security_configuration, code_security_sku_enabled: true)
      refute config.valid?
    end

    test "prohibits use of secret_protection_sku_enabled" do
      config = build(:security_configuration, secret_protection_sku_enabled: true)
      refute config.valid?
    end

    test "feature options must be valid", skip_enterprise: true do
      valid_options = {
        dependency_graph_autosubmit_action: "enabled",
        dependency_graph_autosubmit_action_options: { "labeled_runners" => true }
      }

      security_config = build(:security_configuration, valid_options)
      assert security_config.valid?

      invalid_options = {
        dependency_graph_autosubmit_action: "enabled",
        dependency_graph_autosubmit_action_options: { "labeled_runners" => "sometimes" }
      }

      security_config = build(:security_configuration, invalid_options)
      refute security_config.valid?

      opt_errors = security_config.errors[:dependency_graph_autosubmit_action_options]
      assert_equal 1, opt_errors.length
      assert_equal "Automatic dependency submission must have the labeled runners option set to true or false.", opt_errors.first.message
    end

    context "uninstalled security products" do
      test "cannot create a record with an uninstalled security product set to enabled" do
        GitHub.stubs(private_vulnerability_reporting_enabled?: false)

        config = build(:security_configuration, private_vulnerability_reporting: "enabled")
        refute config.valid?
      end

      test "cannot create a record with an uninstalled security product set to not_set" do
        GitHub.stubs(private_vulnerability_reporting_enabled?: false)

        config = build(:security_configuration, private_vulnerability_reporting: "not_set")
        refute config.valid?
      end

      test "can create a record with an uninstalled security product set to disabled" do
        GitHub.stubs(private_vulnerability_reporting_enabled?: false)

        config = build(:security_configuration, private_vulnerability_reporting: "disabled")
        assert config.valid?
      end

      test "can create a record without providing an uninstalled security product" do
        GitHub.stubs(private_vulnerability_reporting_enabled?: false)

        config = build(:security_configuration, private_vulnerability_reporting: nil)
        assert config.valid?
        assert_equal "disabled", config.private_vulnerability_reporting
      end

      test "can create a non-GHAS record with a GHAS feature uninstalled" do
        GitHub.stubs(configuration_secret_scanning_enabled?: false)

        config = build(:security_configuration, :non_ghas)

        assert config.valid?
        assert_equal "disabled", config.secret_scanning
      end

      test "can convert a GHAS config to a non-GHAS config that had a non-installed GHAS feature set to enabled" do
        config = create(:security_configuration)

        assert config.valid?
        assert_equal "enabled", config.secret_scanning

        # uninstall secret scanning
        GitHub.stubs(configuration_secret_scanning_enabled?: false)

        config.update(enable_ghas: false, code_scanning: "disabled")

        assert config.valid?
        assert_equal "disabled", config.secret_scanning
        assert_equal "disabled", config.secret_scanning_validity_checks
      end

      test "cannot update a record by changing an uninstalled security product from not_set to enabled" do
        config = create(:security_configuration, :not_set)
        assert_equal "not_set", config.secret_scanning

        # uninstall secret scanning
        GitHub.stubs(configuration_secret_scanning_enabled?: false)

        config.secret_scanning = "enabled"
        refute config.valid?
      end

      test "cannot update a record by changing an uninstalled security product from enabled to disabled" do
        config = create(:security_configuration, code_scanning: "enabled")
        assert_equal "enabled", config.code_scanning

        GitHub.stubs(code_scanning_enabled?: false)

        config.code_scanning = "disabled"
        refute config.valid?
      end

      test "can update a record with an uninstalled security product" do
        config = create(:security_configuration, code_scanning: "enabled")
        assert_equal "enabled", config.code_scanning

        GitHub.stubs(code_scanning_enabled?: false)

        config.name = "new name"
        assert config.valid?
        assert_equal "enabled", config.code_scanning
      end
    end
  end

  context "github recommendation" do
    test "returns true if the config is the github recommendation" do
      assert_equal true, T.must(SecurityConfiguration.github_recommended_configuration).is_github_recommended_configuration?
    end

    test "returns false if the config is not the github recommendation" do
      assert_equal false, SecurityConfiguration.new.is_github_recommended_configuration?
    end
  end unless GitHub.enterprise?

  context ".enables_ghas_features?" do
    test "returns true if enable_ghas is true" do
      security_config = create(:security_configuration, enable_ghas: true)
      assert_predicate security_config, :enables_ghas_features?
    end

    test "returns true if any GHAS features are set to be enabled" do
      security_config = create(:security_configuration, code_scanning: "enabled")
      assert_predicate security_config, :enables_ghas_features?
    end

    test "returns false if no GHAS features are set to be enabled" do
      security_config = create(:security_configuration,
        enable_ghas: false,
        code_scanning: "disabled",
        code_scanning_delegated_alert_dismissal: "disabled",
        secret_scanning: "disabled",
        secret_scanning_push_protection: "disabled",
        dependabot_alerts: "enabled",
        dependency_graph: "enabled",
      )
      refute_predicate security_config, :enables_ghas_features?
    end
  end

  context "#apply_to_repository" do
    test "returns false when a config is already being attached to the repo" do
      repo = create(:private_repository, :minimal)
      security_config = create(:security_configuration, target: @org)
      create(:repository_security_configuration, user: @org, state: :attaching, repository: repo)

      assert_no_enqueued_jobs do
        refute security_config.apply_to_repository(@org.admin, repo, @org), "Expected #apply_to_repository to return false"
      end
    end

    test "returns false when a config is already applied to the repo and override_existing_config is false" do
      repo = create(:private_repository, :minimal)
      security_config = create(:security_configuration, target: @org)
      repo_security_config = create(:repository_security_configuration, user: @org, state: :attached, repository: repo)

      assert_no_enqueued_jobs do
        refute security_config.apply_to_repository(@org.admin, repo, @org, override_existing_config: false), "Expected #apply_to_repository to return false"
      end

      repo_security_config.enforced!
      assert_no_enqueued_jobs do
        refute security_config.apply_to_repository(@org.admin, repo, @org, override_existing_config: false), "Expected #apply_to_repository to return false"
      end
    end

    test "replaces any existing repo security config record and enqueues job to apply the config when override_existing_config is true" do
      repo = create(:private_repository, :minimal)
      security_config = create(:security_configuration, target: @org)
      repo_security_config = create(:repository_security_configuration, user: @org, state: :attached, repository: repo)

      assert_enqueued_jobs 1, only: [ApplySecurityConfigurationToRepositoryJob] do
        assert security_config.apply_to_repository(@org.admin, repo, @org, override_existing_config: true)
      end

      assert_nil RepositorySecurityConfiguration.find_by(id: repo_security_config.id)
      assert_predicate RepositorySecurityConfiguration.find_by(repository_id: repo.id, security_configuration_id: security_config.id), :attaching?
    end
  end

  context "#enforced?" do
    test "for an org scoped config, returns false by default" do
      security_config = create(:security_configuration, target: @org)
      refute security_config.enforced?(@org)
    end

    test "for an org scoped config, returns false when marked as unenforced" do
      security_config = create(:security_configuration, :not_enforced, target: @org)
      refute security_config.enforced?(@org)
    end

    test "for an org scoped config, returns true when marked as enforced" do
      security_config = create(:security_configuration, :enforced, target: @org)
      assert security_config.enforced?(@org)
    end

    test "for an Enterprise level configuration (ELC) scoped config, returns false by default" do
      security_config = create(:security_configuration, target: @business)
      refute security_config.enforced?(@business)
      refute security_config.enforced?(@org)
    end

    test "for an ELC scoped config, returns false when marked as unenforced at the enterprise level" do
      security_config = create(:security_configuration, :not_enforced, target: @business)
      refute security_config.enforced?(@business)
      refute security_config.enforced?(@org)
    end

    test "for an ELC scoped config, returns true when marked as enforced at the enterprise level" do
      security_config = create(:security_configuration, :enforced, target: @business)
      assert security_config.enforced?(@business)
      assert security_config.enforced?(@org)
    end

    test "for an ELC scoped config, returns false when marked as unenforced at the org level" do
      security_config = create(:security_configuration, :enforced, target: @business)
      create(:security_configuration_policy, :not_enforced, security_configuration: security_config, target: @org)
      assert security_config.enforced?(@business)
      refute security_config.enforced?(@org)
    end

    test "for an ELC scoped config, returns true when marked as enforced at the org level" do
      security_config = create(:security_configuration, target: @business)
      create(:security_configuration_policy, :enforced, security_configuration: security_config, target: @org)
      refute security_config.enforced?(@business)
      assert security_config.enforced?(@org)
    end

    test "for an ELC scoped config, returns true when marked as unenforced at the enterprise level but enforced at the org level" do
      security_config = create(:security_configuration, :not_enforced, target: @business)
      create(:security_configuration_policy, :enforced, security_configuration: security_config, target: @org)
      refute security_config.enforced?(@business)
      assert security_config.enforced?(@org)
    end
  end

  context "audit logging instrumentation" do
    test "instruments custom config creation" do
      events = subscribe "security_configuration.create"

      custom_config = create(:security_configuration)

      assert event = events.pop, "an event was expected"
      assert_equal custom_config.id, event.payload[:security_configuration_id]
      assert_equal custom_config.target_id, event.payload[:org_id]
    end

    test "does not instrument GitHub recommended config creation", skip_enterprise: true do
      T.must(SecurityConfiguration.github_recommended_configuration).delete
      events = subscribe "security_configuration.create"

      config = T.cast(SecurityConfiguration.create_github_recommended_configuration, SecurityConfiguration)

      assert_nil events.pop, "an event should not have been instrumented"
      assert_equal config.id, T.must(SecurityConfiguration.github_recommended_configuration).id
    end

    test "instruments custom config update" do
      events = subscribe "security_configuration.update"

      custom_config = create(:security_configuration)
      custom_config.update(name: "big orca")

      assert event = events.pop, "an event was expected"
      assert_equal custom_config.id, event.payload[:security_configuration_id]
      assert_equal custom_config.target_id, event.payload[:org_id]
      assert_equal custom_config.name, event.payload[:security_configuration_name]
    end

    test "does not instrument GitHub recommended config update", skip_enterprise: true do
      events = subscribe "security_configuration.update"

      config = SecurityConfiguration.github_recommended_configuration
      T.must(config).update(code_scanning: "disabled")

      assert_nil events.pop, "an event should not have been instrumented"
      assert_equal "disabled", T.must(config).code_scanning
    end

    test "instruments custom config deletion" do
      events = subscribe "security_configuration.delete"

      custom_config = create(:security_configuration)
      custom_config.destroy

      assert event = events.pop, "an event was expected"
      assert_equal custom_config.id, event.payload[:security_configuration_id]
      assert_equal custom_config.target_id, event.payload[:org_id]
    end
  end

  context "unbundling", skip_enterprise: true do
    test "a GHAS enabled config can be unbundled" do
      config = create(:security_configuration, target: @org, enable_ghas: true)

      assert config.enable_ghas
      assert_equal "enabled", config.secret_scanning
      assert_equal "enabled", config.code_scanning

      unbundled_config = config.unbundle!

      assert_equal config.id, unbundled_config.id
      assert_instance_of UnbundledSecurityConfiguration, unbundled_config

      refute unbundled_config.enable_ghas
      assert unbundled_config.secret_protection_sku_enabled
      assert unbundled_config.code_security_sku_enabled

      assert_equal "enabled", unbundled_config.secret_scanning
      assert_equal "enabled", unbundled_config.code_scanning
    end

    test "a config without secret_scanning with null NPP can be unbundled" do
      config = T.let(create(
        :security_configuration,
        target: @org,
        enable_ghas: true,
        secret_scanning: :disabled,
        secret_scanning_push_protection: :disabled,
        secret_scanning_non_provider_patterns: nil
      ), SecurityConfiguration)

      assert config.enable_ghas
      assert_equal "disabled", config.secret_scanning
      assert_nil config.secret_scanning_non_provider_patterns

      unbundled_config = config.unbundle!

      assert_equal config.id, unbundled_config.id
      assert_instance_of UnbundledSecurityConfiguration, unbundled_config

      refute unbundled_config.enable_ghas
      assert unbundled_config.secret_protection_sku_enabled

      assert_equal "disabled", unbundled_config.secret_scanning
      assert_nil unbundled_config.secret_scanning_non_provider_patterns
    end

    test "a ghas disabled config without secret_scanning with null NPP can be unbundled" do
      config = T.let(create(
          :security_configuration,
          :disabled,
          target: @org,
          enable_ghas: false,
          secret_scanning_non_provider_patterns: nil
        ), SecurityConfiguration)

      refute config.enable_ghas
      assert_equal "disabled", config.secret_scanning
      assert_nil config.secret_scanning_non_provider_patterns

      unbundled_config = config.unbundle!
      unbundled_config.save!

      assert_equal config.id, unbundled_config.id
      assert_instance_of UnbundledSecurityConfiguration, unbundled_config

      refute unbundled_config.enable_ghas
      refute unbundled_config.secret_protection_sku_enabled

      assert_equal "disabled", unbundled_config.secret_scanning
      assert_nil unbundled_config.secret_scanning_non_provider_patterns
    end

    test "a non-GHAS enabled config can be unbundled" do
      config = create(:security_configuration, :disabled, target: @org, enable_ghas: false)

      refute config.enable_ghas
      assert_equal "disabled", config.secret_scanning
      assert_equal "disabled", config.code_scanning

      unbundled_config = config.unbundle!

      assert_equal config.id, unbundled_config.id
      assert_instance_of UnbundledSecurityConfiguration, unbundled_config

      refute unbundled_config.enable_ghas
      refute unbundled_config.secret_protection_sku_enabled
      refute unbundled_config.code_security_sku_enabled

      assert_equal "disabled", unbundled_config.secret_scanning
      assert_equal "disabled", unbundled_config.code_scanning
    end

    test "the GHR can't be unbundled" do
      assert_raises ArgumentError do
        SecurityConfiguration.github_recommended_configuration&.unbundle!
      end
    end

    test "an unbundled config can't be unbundled" do
      config = create(:unbundled_security_configuration, target: @org)

      assert_raises ArgumentError do
        config.unbundle!
      end
    end
  end
end
