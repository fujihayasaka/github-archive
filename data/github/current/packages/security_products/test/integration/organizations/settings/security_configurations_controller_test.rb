# typed: true
# frozen_string_literal: true

require "test_helper"

class Organizations::Settings::SecurityConfigurationsControllerTest < GitHub::IntegrationTestCase
  include GitHub::ReactPayloadHelper
  include AuditLog::IntegrationTestHelpers
  include SecurityProductsEnablement::EnterpriseTestHelpers
  include SecurityProductsEnablementHelpers
  include HydroMessageJobTestHelpers
  include TurboghasHelpers

  setup do
    unless GitHub.enterprise?
      enable_feature_flag(:secret_scanning_generic_secrets_in_security_configurations)
      SecretScanning::Features::Owner::ValidityChecks.any_instance.stubs(:feature_available?).returns(true)
    end
    SecretScanning::Features::Org::DelegatedClosures.any_instance.stubs(:feature_available?).returns(true)
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
    @business = create(:business)
    @owner = create(:user, name: "org-owner")
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
    test "renders 404 for users who are not a memeber of the organization" do
      as @random_user
      get "/organizations/#{@org.display_login}/settings/security_products/configurations/new"

      assert_response :not_found
    end

    test "renders 404 for org members who don't have access" do
      as @member
      get "/organizations/#{@org.display_login}/settings/security_products/configurations/new"

      assert_response :not_found
    end

    test "renders for security managers" do
      as @security_manager
      get "/organizations/#{@org.display_login}/settings/security_products/configurations/new"

      assert_response :success
    end

    test "renders for an org admin" do
      as @owner
      get "/organizations/#{@org.display_login}/settings/security_products/configurations/new"

      assert_response :success
    end

    test "payload includes organization name" do
      as @owner
      get "/organizations/#{@org.display_login}/settings/security_products/configurations/new"

      assert_react_payload_equal :organization, @org.display_login
    end

    test "payload includes feature flag info" do
      as @owner
      get "/organizations/#{@org.display_login}/settings/security_products/configurations/new"

      assert_response :success

      SecurityConfigurations::FeatureFlagHelper.client_feature_flags.each do |flag|
        if @org.feature_enabled?(flag)
          assert_react_feature_flag_enabled(flag)
        end
      end
    end
  end

  context "#create" do
    test "returns 201 response when a security configuration is created" do
      assert_difference -> { SecurityConfiguration.count }, 1 do
        as @owner
        post "/organizations/#{@org.display_login}/settings/security_products/configurations", params: {
          security_configuration: {
            name: "config name",
            description: "config description",
            enable_ghas: true,
            private_vulnerability_reporting: "disabled",
            dependency_graph: "enabled",
            dependency_graph_autosubmit_action: GitHub.dependency_graph_autosubmit_action_enabled? ? "enabled" : "disabled",
            dependency_graph_autosubmit_action_options: { "labeled_runners" => GitHub.dependency_graph_autosubmit_action_enabled? },
            dependabot_alerts: "enabled",
            dependabot_security_updates: "not_set",
            code_scanning: "enabled",
            secret_scanning: "enabled",
            secret_scanning_push_protection: "enabled",
            secret_scanning_delegated_bypass: "enabled",
            secret_scanning_delegated_alert_dismissal: "enabled"
          },
          options: {
            secret_scanning_delegated_bypass: {
              reviewers: []
            }
          }
        }, as: :json

        assert_response :created
      end

      config = SecurityConfiguration.last!
      assert_equal @org, config.target
      assert_equal "config name", config.name
      assert_equal "config description", config.description
      assert config.enable_ghas?, "expected GHAS to be enabled"
      assert config.private_vulnerability_reporting_disabled?, "expected PVR to be disabled"
      assert config.dependency_graph_enabled?, "expected dependency graph to be enabled"
      if GitHub.dependency_graph_autosubmit_action_enabled?
        assert config.dependency_graph_autosubmit_action_enabled?, "expected dependency graph autosubmit action to be enabled"
        assert_equal config.dependency_graph_autosubmit_action_options,
                     { "labeled_runners" => true },
                     "expected dependency graph autosubmit action options to be set"
      else
        assert config.dependency_graph_autosubmit_action_disabled?, "expected dependency graph autosubmit action to be disabled"
        assert_equal config.dependency_graph_autosubmit_action_options,
                     { "labeled_runners" => false },
                     "expected dependency graph autosubmit action options to be defaulted"
      end
      assert config.dependabot_alerts_enabled?, "expected dependabot alerts to be enabled"
      assert config.dependabot_security_updates_not_set?, "expected dependabot security updates to be not set"
      assert config.code_scanning_enabled?, "expected code scanning to be enabled"
      assert config.secret_scanning_enabled?, "expected secret scanning to be enabled"
      assert config.secret_scanning_push_protection_enabled?, "expected secret scanning push protection to be enabled"
      assert config.secret_scanning_delegated_bypass_enabled?, "expected secret scanning delegated bypass to be enabled"
      assert config.secret_scanning_delegated_alert_dismissal_enabled?, "expected secret scanning delegated alert closures to be enabled"

    end

    test "returns 201 response when a security configuration can be created, and also set as default for new repos" do
      assert_difference -> { SecurityConfiguration.count }, 1 do
        as @owner
        post "/organizations/#{@org.display_login}/settings/security_products/configurations", params: {
          security_configuration: {
            name: "config name",
            description: "config description",
            enable_ghas: true,
            private_vulnerability_reporting: "disabled",
            dependency_graph: "enabled",
            dependency_graph_autosubmit_action: GitHub.dependency_graph_autosubmit_action_enabled? ? "enabled" : "disabled",
            dependency_graph_autosubmit_action_options: {
              labeled_runners: false
            },
            dependabot_alerts: "enabled",
            dependabot_security_updates: "not_set",
            code_scanning: "enabled",
            secret_scanning: "enabled",
            secret_scanning_push_protection: "enabled",
            secret_scanning_delegated_bypass: "not_set",
            secret_scanning_delegated_alert_dismissal: "not_set",
          },
          default_for_new_public_repos: true,
          default_for_new_private_repos: true
        }, as: :json

        assert_response :created
      end

      config = SecurityConfiguration.last!
      assert_equal @org, config.target

      assert_equal 1, config.security_configuration_defaults.default_for_new_public_and_private_repos.count
      assert_empty config.security_configuration_policies
    end

    test "returns 201 response when a security configuration is set as default for only private and internal repositories" do
      assert_difference -> { SecurityConfiguration.count }, 1 do
        as @owner
        post "/organizations/#{@org.display_login}/settings/security_products/configurations", params: {
          security_configuration: {
            name: "config name",
            description: "config description",
            enable_ghas: true,
            private_vulnerability_reporting: "disabled",
            dependency_graph: "enabled",
            dependency_graph_autosubmit_action: GitHub.dependency_graph_autosubmit_action_enabled? ? "enabled" : "disabled",
            dependency_graph_autosubmit_action_options: {
              labeled_runners: false
            },
            dependabot_alerts: "enabled",
            dependabot_security_updates: "not_set",
            code_scanning: "enabled",
            secret_scanning: "enabled",
            secret_scanning_push_protection: "enabled",
            secret_scanning_delegated_bypass: "not_set",
            secret_scanning_delegated_alert_dismissal: "not_set",
          },
          default_for_new_public_repos: false,
          default_for_new_private_repos: true,
          enforcement: :not_enforced
        }, as: :json

        assert_response :created
      end

      config = SecurityConfiguration.last!
      assert_equal @org, config.target

      assert_equal 1, config.security_configuration_defaults.count
      assert_equal 1, config.security_configuration_defaults.default_for_new_private_repos.count
      assert_empty config.security_configuration_policies
    end

    test "returns 201 response when a security configuration is enforced" do
      assert_difference -> { SecurityConfiguration.count }, 1 do
        as @owner
        post "/organizations/#{@org.display_login}/settings/security_products/configurations", params: {
          security_configuration: {
            name: "config name",
            description: "config description",
            enable_ghas: true,
            private_vulnerability_reporting: "disabled",
            dependency_graph: "enabled",
            dependency_graph_autosubmit_action: GitHub.dependency_graph_autosubmit_action_enabled? ? "enabled" : "disabled",
            dependency_graph_autosubmit_action_options: {
              labeled_runners: false
            },
            dependabot_alerts: "enabled",
            dependabot_security_updates: "not_set",
            code_scanning: "enabled",
            secret_scanning: "enabled",
            secret_scanning_push_protection: "enabled",
            secret_scanning_delegated_bypass: "not_set",
            secret_scanning_delegated_alert_dismissal: "not_set",
          },
          default_for_new_public_repos: false,
          default_for_new_private_repos: false,
          enforcement: :enforced
        }, as: :json

        assert_response :created
      end

      config = SecurityConfiguration.last!
      assert_equal @org, config.target

      policies = config.security_configuration_policies
      assert_equal 1, policies.count
      assert_equal 1, policies.enforced.count
    end

    test "returns 422 response when a security configuration cannot be created" do
      assert_no_changes -> { SecurityConfiguration.count } do
        as @owner
        post "/organizations/#{@org.display_login}/settings/security_products/configurations", params: {
            security_configuration: {
              name: "config name",
              description: "config description",
              enable_ghas: true,
              private_vulnerability_reporting: "disabled",
              dependency_graph: "enabled",
              dependabot_alerts: "enabled",
              dependabot_security_updates: "not_set",
              code_scanning: "enabled",
              secret_scanning: "enabled",
              secret_scanning_push_protection: "not_a_valid_value",
            }
        }, as: :json

        assert_response :unprocessable_entity
      end
    end

    test "returns error message when parent feature is disabled or required field is blank" do
      assert_no_changes -> { SecurityConfiguration.count } do
        as @owner
        post "/organizations/#{@org.display_login}/settings/security_products/configurations", params: {
            security_configuration: {
              name: "",
              description: "config description",
              enable_ghas: false,
              private_vulnerability_reporting: "disabled",
              dependency_graph: "disabled",
              dependency_graph_autosubmit_action: "disabled",
              dependabot_alerts: "not_set",
              dependabot_security_updates: "disabled",
              code_scanning: "enabled",
              secret_scanning: "not_set",
              secret_scanning_push_protection: "enabled",
              secret_scanning_delegated_bypass: "enabled",
            }
        }, as: :json

        assert_response :unprocessable_entity
        assert_equal({
          "name" => ["can't be blank"],
          "dependabot_alerts" => ["Dependabot alerts must be disabled when Dependency graph is disabled"],
          "secret_scanning_push_protection" => ["Push protection must be disabled when secret scanning is disabled"],
          "enable_ghas" => [SecurityConfigurationValidator.ghas_features_unavailable_error_message],
        }, response.parsed_body["errors"])
      end
    end

    test "returns 422 response when a required parameter is missing" do
      as @owner
      post "/organizations/#{@org.display_login}/settings/security_products/configurations"

      assert_response :unprocessable_entity
    end

    test "creates an audit log entry when creating a configuration" do
      config_params = { security_configuration: {
        name: "config name",
        description: "config description",
        enable_ghas: true,
        private_vulnerability_reporting: "disabled",
        dependency_graph: "enabled",
        dependency_graph_autosubmit_action: GitHub.dependency_graph_autosubmit_action_enabled? ? "enabled" : "disabled",
        dependency_graph_autosubmit_action_options: { labeled_runners: GitHub.dependency_graph_autosubmit_action_enabled? },
        dependabot_alerts: "enabled",
        dependabot_security_updates: "not_set",
        code_scanning: "not_set",
        secret_scanning: "not_set",
        secret_scanning_push_protection: "not_set",
        secret_scanning_delegated_bypass: "not_set",
        secret_scanning_delegated_alert_dismissal: "not_set",
        secret_scanning_validity_checks: GitHub.secret_scanning_validity_checks_available_on_instance? ? "not_set" : "disabled",
        secret_scanning_non_provider_patterns: "not_set",
        }
      }

      as @owner
      events = assert_performed_audit_entries(count: 1, only: EVENTS) do
        assert_difference -> { SecurityConfiguration.count }, 1 do
          post "/organizations/#{@org.display_login}/settings/security_products/configurations",
          params: config_params, as: :json
        end
      end
      event = events.sole

      assert_equal "security_configuration.create", event[:action]
      assert_equal @owner.display_login, event[:actor]
      assert_equal @org.display_login, event[:target]
      assert_equal config_params[:security_configuration][:name], event[:security_configuration_name]
      assert_equal config_params[:security_configuration][:description], event[:security_configuration_description]
      assert_equal config_params[:security_configuration][:enable_ghas], event[:security_configuration_enable_ghas]
      assert_equal config_params[:security_configuration][:private_vulnerability_reporting], event[:security_configuration_private_vulnerability_reporting]
      assert_equal config_params[:security_configuration][:dependency_graph], event[:security_configuration_dependency_graph]
      if GitHub.dependency_graph_autosubmit_action_enabled?
        assert_equal "enabled_for_labeled_runners", event[:security_configuration_dependency_graph_autosubmit_action]
      else
        assert_equal "disabled", event[:security_configuration_dependency_graph_autosubmit_action]
      end
      assert_equal config_params[:security_configuration][:dependabot_alerts], event[:security_configuration_dependabot_alerts]
      assert_equal config_params[:security_configuration][:dependabot_security_updates], event[:security_configuration_dependabot_security_updates]
      assert_equal config_params[:security_configuration][:code_scanning], event[:security_configuration_code_scanning]
      assert_equal config_params[:security_configuration][:secret_scanning], event[:security_configuration_secret_scanning]
      assert_equal config_params[:security_configuration][:secret_scanning_push_protection], event[:security_configuration_secret_scanning_push_protection]
      assert_equal config_params[:security_configuration][:secret_scanning_delegated_bypass], event[:security_configuration_secret_scanning_delegated_bypass]
      assert_equal config_params[:security_configuration][:secret_scanning_validity_checks], event[:security_configuration_secret_scanning_validity_checks]
      assert_equal config_params[:security_configuration][:secret_scanning_non_provider_patterns], event[:security_configuration_secret_scanning_non_provider_patterns]
      assert_equal config_params[:security_configuration][:secret_scanning_delegated_alert_dismissal], event[:security_configuration_secret_scanning_delegated_alert_dismissal]

    end

    context "on enterprise", enterprise_only: true do
      test "can create a security configuration when all products are uninstalled" do
        stub_enterprise_enablement(false)
        stub_secret_scanning(false)
        assert_difference -> { SecurityConfiguration.count }, 1 do
          as @owner
          post "/organizations/#{@org.display_login}/settings/security_products/configurations", params: {
            security_configuration: {
              name: "config name",
              description: "config description",
              enable_ghas: true,
            }
          }, as: :json

          assert_response :created
        end

        config = SecurityConfiguration.last!
        assert_equal @org, config.target
        assert_equal "config name", config.name
        assert_equal "config description", config.description
        assert config.enable_ghas?, "expected GHAS to be enabled"
      end
    end

    context "with an organization with unbundled SKUs" do
      test "can create an UnbundledSecurityConfiguration" do
        setup_entity_as_volume_unbundled(@business)

        assert_difference -> { SecurityConfiguration.count }, 1 do
          as @owner
          post "/organizations/#{@org.display_login}/settings/security_products/configurations", params: {
            security_configuration: {
              name: "Unbundled security configuration",
              description: "I'm saving money!",
              enable_ghas: false,
              code_security_sku_enabled: true,
              secret_protection_sku_enabled: true,
              private_vulnerability_reporting: "disabled",
              dependency_graph: "enabled",
              dependency_graph_autosubmit_action: GitHub.dependency_graph_autosubmit_action_enabled? ? "enabled" : "disabled",
              dependency_graph_autosubmit_action_options: { "labeled_runners" => GitHub.dependency_graph_autosubmit_action_enabled? },
              dependabot_alerts: "enabled",
              dependabot_security_updates: "not_set",
              code_scanning: "enabled",
              secret_scanning: "enabled",
              secret_scanning_push_protection: "enabled",
              secret_scanning_delegated_bypass: "enabled",
              secret_scanning_delegated_alert_dismissal: "enabled"
            }
          }, as: :json

          assert_response :created
        end

        config = SecurityConfiguration.last!
        assert_equal UnbundledSecurityConfiguration, config.class
        assert_equal @org, config.target
        assert_equal "Unbundled security configuration", config.name
        refute config.enable_ghas?, "Expected GHAS to be disabled"
        assert config.code_security_sku_enabled?, "Expected Code Security SKU to be enabled"
        assert config.secret_protection_sku_enabled?, "Expected Secret Protection SKU to be enabled"
      end

      test "audit logs when creating an UnbundledSecurityConfiguration" do
        setup_entity_as_volume_unbundled(@business)
        events = T.let([], T.untyped)

        assert_difference -> { SecurityConfiguration.count }, 1 do
          as @owner
          events = assert_performed_audit_entries(count: 1, only: EVENTS) do
            post "/organizations/#{@org.display_login}/settings/security_products/configurations", params: {
              security_configuration: {
                name: "Unbundled security configuration",
                description: "I'm saving money!",
                enable_ghas: false,
                code_security_sku_enabled: true,
                secret_protection_sku_enabled: true,
                private_vulnerability_reporting: "disabled",
                dependency_graph: "enabled",
                dependency_graph_autosubmit_action: GitHub.dependency_graph_autosubmit_action_enabled? ? "enabled" : "disabled",
                dependency_graph_autosubmit_action_options: { "labeled_runners" => GitHub.dependency_graph_autosubmit_action_enabled? },
                dependabot_alerts: "enabled",
                dependabot_security_updates: "not_set",
                code_scanning: "enabled",
                secret_scanning: "enabled",
                secret_scanning_push_protection: "enabled",
                secret_scanning_delegated_bypass: "enabled",
                secret_scanning_delegated_alert_dismissal: "enabled"
              }
            }, as: :json
            assert_response :created
          end
        end

        config = SecurityConfiguration.last!
        event = events.sole
        assert_equal "security_configuration.create", event[:action]
        assert_equal @owner.display_login, event[:actor]
        assert_equal @org.display_login, event[:org]
        assert_equal @org.id, event[:org_id]
        assert_equal config.name, event[:security_configuration_name]
        assert_equal config.description, event[:security_configuration_description]
        assert_equal config.enable_ghas, event[:security_configuration_enable_ghas]
        assert_equal config.code_security_sku_enabled, event[:security_configuration_code_security_sku_enabled]
        assert_equal config.secret_protection_sku_enabled, event[:security_configuration_secret_protection_sku_enabled]
      end

      test "cannot create a GHAS enabled configuration for an org with an unbundled SKU" do
        setup_entity_as_volume_unbundled(@business)

        assert_no_difference -> { SecurityConfiguration.count } do
          as @owner
          post "/organizations/#{@org.display_login}/settings/security_products/configurations", params: {
            security_configuration: {
              name: "I'm a naughty user who's manually editing requests",
              description: "Bad, bad user!",
              enable_ghas: true,
              # Skipping the SKU-specific enable attrs.
              private_vulnerability_reporting: "disabled",
              dependency_graph: "enabled",
              dependency_graph_autosubmit_action: GitHub.dependency_graph_autosubmit_action_enabled? ? "enabled" : "disabled",
              dependency_graph_autosubmit_action_options: { "labeled_runners" => GitHub.dependency_graph_autosubmit_action_enabled? },
              dependabot_alerts: "enabled",
              dependabot_security_updates: "not_set",
              code_scanning: "enabled",
              secret_scanning: "enabled",
              secret_scanning_push_protection: "enabled",
              secret_scanning_delegated_bypass: "enabled",
              secret_scanning_delegated_alert_dismissal: "enabled"
            }
          }, as: :json

          assert_response :unprocessable_entity

          # Ensure that the enable_ghas flag is returning the correct error:
          assert_equal(
            ["This entity is not eligible to use the bundled GitHub Advanced Security product. Use `code_security_sku_enabled` and `secret_protection_sku_enabled` instead."],
            response.parsed_body["errors"]["enable_ghas"]
          )

          # Ensure code_security_sku_enabled and secret_protection_sku_enabled are returning errors as well.
          # Intentionally only checking for keys, because as we add security products their messages will change.
          assert_equal(
            %w(enable_ghas code_security_sku_enabled secret_protection_sku_enabled),
            response.parsed_body["errors"].keys
          )
        end
      end
    end
  end

  context "#edit" do
    test "payload includes organization name and security config" do
      config = create(:security_configuration, target: @org)
      as @owner
      get "/organizations/#{@org.display_login}/settings/security_products/configurations/edit/#{config.id}"

      expected_payload = {
        "id" => config.id,
        "name" => config.name,
        "description" => config.description,
        "default_for_new_public_repos" => false,
        "default_for_new_private_repos" => false,
        "enforcement" => "not_enforced",
        "target_type" => config.target_type,
        "private_vulnerability_reporting" => GitHub.private_vulnerability_reporting_enabled? ? "enabled" : "disabled",
        "dependency_graph" => "enabled",
        "dependency_graph_autosubmit_action" => "disabled",
        "dependency_graph_autosubmit_action_options" => { "labeled_runners" => false },
        "dependabot_alerts" => "enabled",
        "dependabot_security_updates" => "enabled",
        "code_scanning" => "enabled",
        "code_scanning_delegated_alert_dismissal" => "disabled",
        "code_scanning_options" => { "runner_type" => "not_set", "runner_label" => nil },
        "secret_scanning" => "enabled",
        "secret_scanning_push_protection" => "enabled",
        "secret_scanning_delegated_bypass" => "disabled",
        "secret_scanning_non_provider_patterns" => "disabled",
        "secret_scanning_delegated_alert_dismissal" => "disabled",
        "enable_ghas" => true,
        "code_security_sku_enabled" => false,
        "secret_protection_sku_enabled" => false,
        "repositories_count" => 0
      }

      unless GitHub.enterprise?
        expected_payload["secret_scanning_validity_checks"] = "disabled"
        expected_payload["secret_scanning_generic_secrets"] = "disabled"
      end

      assert_react_payload_equal :organization, @org.display_login
      assert_react_payload_equal(:security_configuration, expected_payload)
    end

    test "payload indicates if enablement changes are in progress" do
      config = create(:security_configuration, target: @org)
      Organization.any_instance.expects(:security_configurations_blocked?).returns(true)

      as @owner
      get "/organizations/#{@org.display_login}/settings/security_products/configurations/edit/#{config.id}"

      assert_react_payload_equal :changesInProgress, { "inProgress" => true, "type" => "enablement_changes" }
    end

    test "payload indicates if a configuration is being applied" do
      config = create(:security_configuration, target: @org)
      Organization.any_instance.expects(:jobs_in_progress?).returns(true)

      as @owner
      get "/organizations/#{@org.display_login}/settings/security_products/configurations/edit/#{config.id}"

      assert_react_payload_equal :changesInProgress, { "inProgress" => true, "type" => "applying_configuration" }
    end

    test "payload includes feature flag info" do
      config = create(:security_configuration, target: @org)
      as @owner
      get "/organizations/#{@org.display_login}/settings/security_products/configurations/edit/#{config.id}"

      SecurityConfigurations::FeatureFlagHelper.client_feature_flags.each do |flag|
        if @org.feature_enabled?(flag)
          assert_react_feature_flag_enabled(flag)
        end
      end
    end
  end

  context "#update" do
    test "returns 200 response when a security configuration is updated" do
      config = create(:security_configuration, target: @org)

      assert_no_difference -> { SecurityConfiguration.count } do
        as @owner
        put "/organizations/#{@org.display_login}/settings/security_products/configurations/#{config.id}", params: {
          security_configuration: {
            name: "config name",
            description: "config description",
            enable_ghas: true,
            private_vulnerability_reporting: "disabled",
            dependency_graph: "disabled",
            dependency_graph_autosubmit_action: "disabled",
            dependabot_alerts: "disabled",
            dependabot_security_updates: "disabled",
            code_scanning: "enabled",
            code_scanning_delegated_alert_dismissal: "disabled",
            secret_scanning: "not_set",
            secret_scanning_push_protection: "not_set",
          }
        }, as: :json

        assert_response :ok
      end

      config.reload
      assert_equal @org, config.target
      assert_equal "config name", config.name
      assert_equal "config description", config.description
      assert config.enable_ghas?, "expected GHAS to be enabled"
      assert config.private_vulnerability_reporting_disabled?, "expected PVR to be disabled"
      assert config.dependency_graph_disabled?, "expected dependency graph to be disabled"
      assert config.dependabot_alerts_disabled?, "expected dependabot alerts to be disabled"
      assert config.dependabot_security_updates_disabled?, "expected dependabot security updates to be disabled"
      assert config.code_scanning_enabled?, "expected code scanning to be enabled"
      assert config.code_scanning_delegated_alert_dismissal_disabled?, "expected code scanning delegated alert dismissal to be disabled"
      assert config.secret_scanning_not_set?, "expected secret scanning to be not set"
      assert config.secret_scanning_push_protection_not_set?, "expected secret scanning push protection to be not_set"
    end

    test "successfully updates the settings of repositories attached to the configuration" do
      config = create(
        :security_configuration,
        target: @org,
        enable_ghas: false,
        private_vulnerability_reporting: "disabled",
        dependency_graph: "enabled",
        dependency_graph_autosubmit_action: "disabled",
        dependency_graph_autosubmit_action_options: { "labeled_runners" => false },
        dependabot_alerts: "disabled",
        dependabot_security_updates: "disabled",
        code_scanning: "disabled",
        code_scanning_delegated_alert_dismissal: "disabled",
        secret_scanning: "disabled",
        secret_scanning_push_protection: "disabled",
        secret_scanning_delegated_bypass: "disabled",
        secret_scanning_delegated_alert_dismissal: "disabled"
      )
      repo = create(:private_repository, owner: @org)

      # Stub this to return false so that the job enqueued (but not run) above doesn't block our request:
      Organization.any_instance.stubs(:security_configurations_applying_or_blocked?).returns(false)

      # Apply the configuration to a repository
      perform_enqueued_jobs(only: [SecurityProductsEnablement::OrganizationSecurityConfigurationJob, ApplySecurityConfigurationToRepositoryJob]) do
        as @owner
        put "/organizations/#{@org.display_login}/settings/security_products/configuration/#{config.id}/repositories",
          params: { repository_ids: [repo.id] }, as: :json

        assert_response :created
      end

      repo.reload
      refute_predicate repo, :advanced_security_enabled?
      refute_predicate repo, :vulnerability_alerts_enabled?
      refute_predicate repo, :vulnerability_updates_enabled?

      # Update the configuration: enable dependency graph and dependabot alerts
      perform_enqueued_jobs(only: [SecurityProductsEnablement::OrganizationSecurityConfigurationJob, ApplySecurityConfigurationToRepositoryJob]) do
        keys = SharedSecurityConfigurationsDependency::PERMITTED_PARAMS.map(&:to_s)
        params = config.attributes.slice(*keys).merge({
          dependabot_alerts: "enabled",
          dependabot_security_updates: "enabled",
        })

        as @owner
        put "/organizations/#{@org.display_login}/settings/security_products/configurations/#{config.id}",
          params: { security_configuration: params }, as: :json

        assert_response :ok
      end

      repo.reload
      refute_predicate repo, :advanced_security_enabled?
      assert_predicate repo, :vulnerability_alerts_enabled?
      assert_predicate repo, :vulnerability_updates_enabled?
    end

    test "successfully updates the settings of repositories attached to the configuration when an option is changed" do
      setup_entity_as_bundled_ghas(@business)
      config = create(
        :security_configuration,
        target: @org,
        enable_ghas: true,
        private_vulnerability_reporting: "disabled",
        dependency_graph: "disabled",
        dependency_graph_autosubmit_action: "disabled",
        dependency_graph_autosubmit_action_options: { "labeled_runners" => false },
        dependabot_alerts: "disabled",
        dependabot_security_updates: "disabled",
        code_scanning: "enabled",
        code_scanning_options: { "runner_type" => "not_set", "runner_label" => nil },
        secret_scanning: "disabled",
        secret_scanning_push_protection: "disabled",
        secret_scanning_delegated_bypass: "disabled",
        secret_scanning_delegated_alert_dismissal: "disabled"
      )
      repo = create(:private_repository, owner: @org)

      # Stub this to return false so that the job enqueued (but not run) above doesn't block our request:
      Organization.any_instance.stubs(:security_configurations_applying_or_blocked?).returns(false)

      stub_auto_codeql
      stub_turboghas_summary(maximum_committers: 3, active_committers: 2)

      VCR.use_cassette "code-scanning/counts-absent" do
        VCR.use_cassette("code-scanning/get-managed-analysis-info-disabled", persist_with: :turboscan) do
          # Apply the configuration to a repository
          perform_enqueued_jobs(only: [SecurityProductsEnablement::OrganizationSecurityConfigurationJob, ApplySecurityConfigurationToRepositoryJob]) do
            as @owner
            put "/organizations/#{@org.display_login}/settings/security_products/configuration/#{config.id}/repositories",
              params: { repository_ids: [repo.id] }, as: :json

            assert_response :created
          end
        end
      end

      repo.reload
      assert_predicate repo, :advanced_security_enabled?
      assert_predicate repo, :code_scanning_enabled?

      # Update the configuration: enable dependency graph and dependabot alerts
      body_params_matcher = lambda do |actual, _|
        actual_body = Turboscan::Proto::UpdateRequest.decode_json(actual.body)
        actual_body.runner_type == :RUNNER_TYPE_LABELED && actual_body.runner_label == "other-custom-runner"
      end

      VCR.use_cassette("code-scanning/managed-analyses-update", persist_with: :turboscan, match_requests_on: [:method, :uri, body_params_matcher]) do
        VCR.use_cassette("code-scanning/get-managed-analysis-info-runner-label-custom", persist_with: :turboscan) do
          perform_enqueued_jobs(only: [ApplySecurityConfigurationToRepositoryJob, SecurityProductsEnablement::OrganizationSecurityConfigurationJob, ApplySecurityConfigurationToRepositoryJob]) do
            keys = SharedSecurityConfigurationsDependency::PERMITTED_PARAMS.map(&:to_s)
            params = config.attributes.slice(*keys).merge({
              code_scanning_options: { "runner_type" => "labeled", "runner_label" => "other-custom-runner" },
            })

            as @owner
            put "/organizations/#{@org.display_login}/settings/security_products/configurations/#{config.id}",
              params: { security_configuration: params }, as: :json

            assert_response :ok
          end
        end
      end

      repo.reload
      assert_predicate repo, :advanced_security_enabled?
      assert_predicate repo, :code_scanning_enabled?
    end

    test "returns 200 response when a security configuration is set as default for new public, private and internal repositories" do
      config = create(:security_configuration, target: @org)

      assert_no_difference -> { SecurityConfiguration.count } do
        as @owner
        put "/organizations/#{@org.display_login}/settings/security_products/configurations/#{config.id}", params: {
          security_configuration: {
            name: "config name",
            description: "config description",
            enable_ghas: true,
            private_vulnerability_reporting: "disabled",
            dependency_graph: "disabled",
            dependabot_alerts: "disabled",
            dependabot_security_updates: "disabled",
            code_scanning: "enabled",
            secret_scanning: "not_set",
            secret_scanning_push_protection: "not_set",
            secret_scanning_delegated_bypass: "disabled",
            secret_scanning_delegated_alert_dismissal: "disabled"
          },
          default_for_new_public_repos: true,
          default_for_new_private_repos: true
        }, as: :json

        assert_response :ok
      end

      assert_equal 1, config.security_configuration_defaults.default_for_new_public_and_private_repos.count
    end

    test "returns 200 response when a security configuration is set as default for only private and internal repositories" do
      config = create(:security_configuration, target: @org)

      assert_no_difference -> { SecurityConfiguration.count } do
        as @owner
        put "/organizations/#{@org.display_login}/settings/security_products/configurations/#{config.id}", params: {
          security_configuration: {
            name: "config name",
            description: "config description",
            enable_ghas: true,
            private_vulnerability_reporting: "disabled",
            dependency_graph: "disabled",
            dependabot_alerts: "disabled",
            dependabot_security_updates: "disabled",
            code_scanning: "enabled",
            secret_scanning: "not_set",
            secret_scanning_push_protection: "not_set",
            secret_scanning_delegated_bypass: "disabled",
            secret_scanning_delegated_alert_dismissal: "disabled"
          },
          default_for_new_public_repos: false,
          default_for_new_private_repos: true
        }, as: :json

        assert_response :ok
      end

      assert_equal 1, config.security_configuration_defaults.count
      assert_equal 1, config.security_configuration_defaults.default_for_new_private_repos.count
    end

    test "successfully updates an enterprise level configuration's defaults" do
      config = create(:security_configuration, target: @business)

      assert_equal 0, config.security_configuration_defaults.count

      assert_no_difference -> { SecurityConfiguration.count } do
        as @owner
        put "/organizations/#{@org.display_login}/settings/security_products/configurations/#{config.id}", params: {
          security_configuration: {
            name: config.name,
            description: config.description,
            enable_ghas: config.enable_ghas,
            private_vulnerability_reporting: config.private_vulnerability_reporting,
            dependency_graph: config.dependency_graph,
            dependabot_alerts: config.dependabot_alerts,
            dependabot_security_updates: config.dependabot_security_updates,
            code_scanning: config.code_scanning,
            secret_scanning: config.secret_scanning,
            secret_scanning_push_protection: config.secret_scanning_push_protection,
          },
          default_for_new_public_repos: true,
        }, as: :json
      end

      assert_response :ok
      assert_equal 1, SecurityConfigurationDefault.count

      config_default = SecurityConfigurationDefault.where(security_configuration_id: config.id, target_id: @org.id).first
      assert config_default

      assert T.must(config_default).default_for_new_public_repos
      refute T.must(config_default).default_for_new_private_repos
    end

    test "successfully updates an enterprise level configuration's enforcement" do
      config = create(:security_configuration, target: @business)

      assert_equal 0, config.security_configuration_policies.count

      assert_no_difference -> { SecurityConfiguration.count } do
        as @owner
        put "/organizations/#{@org.display_login}/settings/security_products/configurations/#{config.id}", params: {
          security_configuration: {
            name: config.name,
            description: config.description,
            enable_ghas: config.enable_ghas,
            private_vulnerability_reporting: config.private_vulnerability_reporting,
            dependency_graph: config.dependency_graph,
            dependabot_alerts: config.dependabot_alerts,
            dependabot_security_updates: config.dependabot_security_updates,
            code_scanning: config.code_scanning,
            secret_scanning: config.secret_scanning,
            secret_scanning_push_protection: config.secret_scanning_push_protection,
          },
          enforcement: :enforced
        }, as: :json
      end

      assert_response :ok
      assert_equal 0, SecurityConfigurationDefault.count

      policies = config.security_configuration_policies
      assert_equal 1, policies.count
      assert_equal 1, policies.enforced.count
    end

    test "updates the gh recommended configuration defaults for an org", skip_enterprise: true do
      assert_no_changes -> { @gh_config.reload } do
        as @owner
        put "/organizations/#{@org.display_login}/settings/security_products/configurations/#{@gh_config.id}", params: {
          security_configuration: {
            name: @gh_config.name,
            description: @gh_config.description,
            enable_ghas: @gh_config.enable_ghas,
            private_vulnerability_reporting: @gh_config.private_vulnerability_reporting,
            dependency_graph: @gh_config.dependency_graph,
            dependabot_alerts: @gh_config.dependabot_alerts,
            dependabot_security_updates: @gh_config.dependabot_security_updates,
            code_scanning: @gh_config.code_scanning,
            secret_scanning: @gh_config.secret_scanning,
            secret_scanning_push_protection: @gh_config.secret_scanning_push_protection,
          },
          default_for_new_public_repos: true,
          default_for_new_private_repos: false,
          enforcement: :not_enforced
        }, as: :json

        assert_response :ok
      end

      assert_equal 1, SecurityConfiguration.count
      assert_equal 1, SecurityConfigurationDefault.count
      config_default = SecurityConfigurationDefault.where(security_configuration_id: @gh_config.id, target_id: @org.id).first
      assert config_default
      assert T.must(config_default).default_for_new_public_repos
      refute T.must(config_default).default_for_new_private_repos

      policies = @gh_config.security_configuration_policies
      assert_equal 1, policies.count
      assert_equal 1, policies.not_enforced.count
    end

    test "updates the gh recommended configuration to mark it as enforced", skip_enterprise: true do
      assert_no_changes -> { @gh_config.reload } do
        as @owner
        put "/organizations/#{@org.display_login}/settings/security_products/configurations/#{@gh_config.id}", params: {
          security_configuration: {
            name: @gh_config.name,
            description: @gh_config.description,
            enable_ghas: @gh_config.enable_ghas,
            private_vulnerability_reporting: @gh_config.private_vulnerability_reporting,
            dependency_graph: @gh_config.dependency_graph,
            dependabot_alerts: @gh_config.dependabot_alerts,
            dependabot_security_updates: @gh_config.dependabot_security_updates,
            code_scanning: @gh_config.code_scanning,
            secret_scanning: @gh_config.secret_scanning,
            secret_scanning_push_protection: @gh_config.secret_scanning_push_protection,
          },
          default_for_new_public_repos: false,
          default_for_new_private_repos: false,
          enforcement: :enforced
        }, as: :json

        assert_response :ok
      end

      assert_equal 1, SecurityConfiguration.count
      assert_equal 0, SecurityConfigurationDefault.count

      policies = @gh_config.security_configuration_policies
      assert_equal 1, policies.count
      assert_equal 1, policies.enforced.count
    end

    test "returns 404 response when trying to update a configuration that does not belong to the current organization" do
      config = create(:security_configuration)

      assert_no_difference -> { SecurityConfiguration.count } do
        as @owner
        put "/organizations/#{@org.display_login}/settings/security_products/configurations/#{config.id}", params: {
          security_configuration: {
            name: "config name",
            description: "config description",
            enable_ghas: true,
            private_vulnerability_reporting: "disabled",
            dependency_graph: "disabled",
            dependabot_alerts: "disabled",
            dependabot_security_updates: "disabled",
            code_scanning: "enabled",
            secret_scanning: "not_set",
            secret_scanning_push_protection: "not_set",
          }
        }, as: :json

        assert_response :not_found
      end

      assert_equal config, SecurityConfiguration.find_by(id: config.id)
    end

    test "returns 422 response when a security configuration cannot be updated" do
      config = create(:security_configuration, target: @org)

      assert_no_difference -> { SecurityConfiguration.count } do
        as @owner
        put "/organizations/#{@org.display_login}/settings/security_products/configurations/#{config.id}", params: {
          security_configuration: {
            name: "config name",
            description: "config description",
            enable_ghas: true,
            private_vulnerability_reporting: "disabled",
            dependency_graph:  "not_a_valid_value", # this value is invalid and prevents the config from being saved,
            dependabot_alerts: "disabled",
            dependabot_security_updates: "disabled",
            code_scanning: "enabled",
            secret_scanning: "not_set",
            secret_scanning_push_protection: "not_set",
          }
        }, as: :json

        assert_response :unprocessable_entity
      end

      assert_equal config, SecurityConfiguration.find_by(id: config.id)
    end

    test "returns error messages when parent feature is disabled or required field is blank" do
      config = create(:security_configuration, target: @org)

      assert_no_difference -> { SecurityConfiguration.count } do
        as @owner
        put "/organizations/#{@org.display_login}/settings/security_products/configurations/#{config.id}", params: {
          security_configuration: {
            name: "",
            description: "config description",
            enable_ghas: false,
            private_vulnerability_reporting: "disabled",
            dependency_graph: "disabled",
            dependency_graph_autosubmit_action: "disabled",
            dependabot_alerts: "not_set",
            dependabot_security_updates: "disabled",
            code_scanning: "enabled",
            secret_scanning: "disabled",
            secret_scanning_push_protection: "enabled",
          }
        }, as: :json

        assert_response :unprocessable_entity
        assert_equal({
          "name" => ["can't be blank"],
          "dependabot_alerts" => ["Dependabot alerts must be disabled when Dependency graph is disabled"],
          "secret_scanning_push_protection" => ["Push protection must be disabled when secret scanning is disabled"],
          "enable_ghas" => [SecurityConfigurationValidator.ghas_features_unavailable_error_message],
        }, response.parsed_body["errors"])
      end

      assert_equal config, SecurityConfiguration.find_by(id: config.id)
    end

    test "returns 422 if security configurations are being applied on the org" do
      # Pretend configurations are being applied to the org:
      job_progress_tracker = SecurityProductsEnablement::JobProgressTracker.new(@org.id)
      job_progress_tracker.start

      gh_config = create(:security_configuration, target: @org)

      as @owner
      put "/organizations/#{@org.display_login}/settings/security_products/configurations/#{gh_config.id}", params: {
        security_configuration: {
          name: gh_config.name,
          description: gh_config.description,
          enable_ghas: gh_config.enable_ghas,
          private_vulnerability_reporting: gh_config.private_vulnerability_reporting,
          dependency_graph: gh_config.dependency_graph,
          dependabot_alerts: gh_config.dependabot_alerts,
          dependabot_security_updates: gh_config.dependabot_security_updates,
          code_scanning: gh_config.code_scanning,
          secret_scanning: gh_config.secret_scanning,
          secret_scanning_push_protection: gh_config.secret_scanning_push_protection,
        },
        default_for_new_public_repos: true,
        default_for_new_private_repos: false
      }, as: :json

      assert_response :unprocessable_entity
    end

    test "returns 422 if BlockedSettings are active for the org" do
      # Pretend configurations are being blocked:
      job_status = SecurityProductsEnablement::JobStatus.create({ id: SecurityAnalysisSettingsUpdateJob.job_id(@org, :auto_codeql_enable_all) })
      gh_config = create(:security_configuration, target: @org)

      as @owner
      put "/organizations/#{@org.display_login}/settings/security_products/configurations/#{gh_config.id}", params: {
        security_configuration: {
          name: gh_config.name,
          description: gh_config.description,
          enable_ghas: gh_config.enable_ghas,
          private_vulnerability_reporting: gh_config.private_vulnerability_reporting,
          dependency_graph: gh_config.dependency_graph,
          dependabot_alerts: gh_config.dependabot_alerts,
          dependabot_security_updates: gh_config.dependabot_security_updates,
          code_scanning: gh_config.code_scanning,
          secret_scanning: gh_config.secret_scanning,
          secret_scanning_push_protection: gh_config.secret_scanning_push_protection,
        },
        default_for_new_public_repos: true,
        default_for_new_private_repos: false
      }, as: :json

      assert_response :unprocessable_entity
    end

    test "returns 422 when updating a config to use a reserved name" do
      config = create(:security_configuration, target: @org)

      as @owner
      put "/organizations/#{@org.display_login}/settings/security_products/configurations/#{config.id}", params: {
          security_configuration: {
            name: "GitHub recommended",
            description: "config description",
            enable_ghas: false,
            private_vulnerability_reporting: "disabled",
            dependency_graph: "disabled",
            dependency_graph_autosubmit_action: "disabled",
            dependabot_alerts: "disabled",
            dependabot_security_updates: "disabled",
            code_scanning: "disabled",
            secret_scanning: "disabled",
            secret_scanning_push_protection: "disabled",
          },
          default_for_new_public_repos: false,
          default_for_new_private_repos: false
      }, as: :json

      assert_response :unprocessable_entity
      assert_equal({
        "name" => ["GitHub recommended is a reserved configuration name"],
      }, response.parsed_body["errors"])
    end

    test "creates an audit log entry when updating a configuration" do
      config = create(:security_configuration, target: @org)

      config_params = { security_configuration: {
        name: "Updated config name",
        description: "Updated a config for audit logging",
        enable_ghas: false,
        private_vulnerability_reporting: "disabled",
        dependency_graph: "disabled",
        dependabot_alerts: "disabled",
        dependabot_security_updates: "disabled",
        code_scanning: "disabled",
        secret_scanning: "disabled",
        secret_scanning_push_protection: "disabled",
        secret_scanning_validity_checks: "disabled",
        }
      }

      as @owner
      events = assert_performed_audit_entries(count: 1, only: EVENTS) do
        assert_difference -> { SecurityConfiguration.count }, 0 do
          put "/organizations/#{@org.display_login}/settings/security_products/configurations/#{config.id}",
            params: config_params, as: :json
        end
      end
      event = events.sole

      assert_equal "security_configuration.update", event[:action]
      assert_equal @owner.display_login, event[:actor]
      assert_equal @org.display_login, event[:target]
      assert_equal config_params[:security_configuration][:name], event[:security_configuration_name]
      assert_equal config_params[:security_configuration][:description], event[:security_configuration_description]
      assert_equal config_params[:security_configuration][:enable_ghas], event[:security_configuration_enable_ghas]
      assert_equal config_params[:security_configuration][:private_vulnerability_reporting], event[:security_configuration_private_vulnerability_reporting]
      assert_equal config_params[:security_configuration][:dependency_graph], event[:security_configuration_dependency_graph]
      assert_equal config_params[:security_configuration][:dependabot_alerts], event[:security_configuration_dependabot_alerts]
      assert_equal config_params[:security_configuration][:dependabot_security_updates], event[:security_configuration_dependabot_security_updates]
      assert_equal config_params[:security_configuration][:code_scanning], event[:security_configuration_code_scanning]
      assert_equal config_params[:security_configuration][:secret_scanning], event[:security_configuration_secret_scanning]
      assert_equal config_params[:security_configuration][:secret_scanning_push_protection], event[:security_configuration_secret_scanning_push_protection]
      assert_equal config_params[:security_configuration][:secret_scanning_validity_checks], event[:security_configuration_secret_scanning_validity_checks]
    end

    test "creates an audit log entry when updating GitHub Recommended config to be enforced", skip_enterprise: true do
      create(:security_configuration_default,
        target: @org,
        default_for_new_public_repos: false,
        default_for_new_private_repos: false,
        security_configuration_id: @gh_config.id,
      )

      create(:security_configuration_policy,
        target: @org,
        enforcement: :not_enforced,
        security_configuration_id: @gh_config.id
      )

      as @owner
      events = assert_performed_audit_entries(count: 1, only: EVENTS) do
        assert_difference -> { SecurityConfiguration.count }, 0 do

          put "/organizations/#{@org.display_login}/settings/security_products/configurations/#{@gh_config.id}", params: {
            security_configuration: {
              name: @gh_config.name,
              description: @gh_config.description,
              enable_ghas: @gh_config.enable_ghas,
              private_vulnerability_reporting: @gh_config.private_vulnerability_reporting,
              dependency_graph: @gh_config.dependency_graph,
              dependabot_alerts: @gh_config.dependabot_alerts,
              dependabot_security_updates: @gh_config.dependabot_security_updates,
              code_scanning: @gh_config.code_scanning,
              secret_scanning: @gh_config.secret_scanning,
              secret_scanning_push_protection: @gh_config.secret_scanning_push_protection,
            },
            default_for_new_public_repos: false,
            default_for_new_private_repos: false,
            enforcement: :enforced
          }, as: :json
        end
      end
      event = events.sole

      assert_equal "security_configuration_policy.update", event[:action]
      assert_equal @owner.display_login, event[:actor]
      assert_equal @org.display_login, event[:target]
      assert_equal "enforced", event[:enforcement]
    end

    test "creates an audit log entry when updating a security configuration to be enforced" do
      config = create(:security_configuration, target: @org)

      create(:security_configuration_policy,
        target: @org,
        enforcement: :not_enforced,
        security_configuration_id: config.id
      )

      as @owner
      events = assert_performed_audit_entries(count: 2, only: EVENTS) do
        assert_difference -> { SecurityConfiguration.count }, 0 do

          put "/organizations/#{@org.display_login}/settings/security_products/configurations/#{config.id}", params: {
            security_configuration: {
              name: config.name,
              description: config.description,
              enable_ghas: config.enable_ghas,
              private_vulnerability_reporting: config.private_vulnerability_reporting,
              dependency_graph: config.dependency_graph,
              dependabot_alerts: config.dependabot_alerts,
              dependabot_security_updates: config.dependabot_security_updates,
              code_scanning: config.code_scanning,
              secret_scanning: config.secret_scanning,
              secret_scanning_push_protection: config.secret_scanning_push_protection,
            },
            default_for_new_public_repos: false,
            default_for_new_private_repos: false,
            enforcement: :enforced
          }, as: :json
        end
      end

      # there are two audit log entries, one for the policy update and one for the configuration update, grab policy
      event = events.find { |e| e[:action] == "security_configuration_policy.update" }

      assert_equal "security_configuration_policy.update", event[:action]
      assert_equal @owner.display_login, event[:actor]
      assert_equal @org.display_login, event[:target]
      assert_equal "enforced", event[:enforcement]
    end

    test "creates an audit log entry when updating the default settings for new public repositories" do
      config = create(:security_configuration, target: @org)

      as @owner
      events = assert_performed_audit_entries(count: 2, only: EVENTS) do
        assert_difference -> { SecurityConfiguration.count }, 0 do

          put "/organizations/#{@org.display_login}/settings/security_products/configurations/#{config.id}", params: {
            security_configuration: {
              name: config.name,
              description: config.description,
              enable_ghas: config.enable_ghas,
              private_vulnerability_reporting: config.private_vulnerability_reporting,
              dependency_graph: config.dependency_graph,
              dependabot_alerts: config.dependabot_alerts,
              dependabot_security_updates: config.dependabot_security_updates,
              code_scanning: config.code_scanning,
              secret_scanning: config.secret_scanning,
              secret_scanning_push_protection: config.secret_scanning_push_protection,
            },
            default_for_new_public_repos: true,
            default_for_new_private_repos: false,
            enforcement: :not_enforced
          }, as: :json
        end
      end

      event = events.find { |e| e[:action] == "security_configuration_default.update" }

      assert_equal "security_configuration_default.update", event[:action]
      assert_equal @owner.display_login, event[:actor]
      assert_equal @org.display_login, event[:target]
      assert_equal config.name, event[:security_configuration_name]
      assert_equal true, event[:default_for_new_public_repos]
      assert_equal false, event[:default_for_new_private_repos]
    end

    test "creates an audit log entry when updating the default settings for new private repositories" do
      config = create(:security_configuration, target: @org)

      as @owner
      events = assert_performed_audit_entries(count: 2, only: EVENTS) do
        assert_difference -> { SecurityConfiguration.count }, 0 do

          put "/organizations/#{@org.display_login}/settings/security_products/configurations/#{config.id}", params: {
            security_configuration: {
              name: config.name,
              description: config.description,
              enable_ghas: config.enable_ghas,
              private_vulnerability_reporting: config.private_vulnerability_reporting,
              dependency_graph: config.dependency_graph,
              dependabot_alerts: config.dependabot_alerts,
              dependabot_security_updates: config.dependabot_security_updates,
              code_scanning: config.code_scanning,
              secret_scanning: config.secret_scanning,
              secret_scanning_push_protection: config.secret_scanning_push_protection,
            },
            default_for_new_public_repos: false,
            default_for_new_private_repos: true,
            enforcement: :not_enforced
          }, as: :json
        end
      end

      event = events.find { |e| e[:action] == "security_configuration_default.update" }

      assert_equal "security_configuration_default.update", event[:action]
      assert_equal @owner.display_login, event[:actor]
      assert_equal @org.display_login, event[:target]
      assert_equal config.name, event[:security_configuration_name]
      assert_equal false, event[:default_for_new_public_repos]
      assert_equal true, event[:default_for_new_private_repos]
    end

    test "creates an audit log entry when updating default settings for all repositories" do
      config = create(:security_configuration, target: @org)

      as @owner
      events = assert_performed_audit_entries(count: 2, only: EVENTS) do
        assert_difference -> { SecurityConfiguration.count }, 0 do

          put "/organizations/#{@org.display_login}/settings/security_products/configurations/#{config.id}", params: {
            security_configuration: {
              name: config.name,
              description: config.description,
              enable_ghas: config.enable_ghas,
              private_vulnerability_reporting: config.private_vulnerability_reporting,
              dependency_graph: config.dependency_graph,
              dependabot_alerts: config.dependabot_alerts,
              dependabot_security_updates: config.dependabot_security_updates,
              code_scanning: config.code_scanning,
              secret_scanning: config.secret_scanning,
              secret_scanning_push_protection: config.secret_scanning_push_protection,
            },
            default_for_new_public_repos: true,
            default_for_new_private_repos: true,
            enforcement: :not_enforced
          }, as: :json
        end
      end

      event = events.find { |e| e[:action] == "security_configuration_default.update" }

      assert_equal "security_configuration_default.update", event[:action]
      assert_equal @owner.display_login, event[:actor]
      assert_equal @org.display_login, event[:target]
      assert_equal config.name, event[:security_configuration_name]
      assert_equal true, event[:default_for_new_public_repos]
      assert_equal true, event[:default_for_new_private_repos]
    end

    test "creates an audit log entry when updating default settings to none for newly created repositories" do
      config = create(:security_configuration, target: @org)
      default_config = create(:security_configuration_default, security_configuration: config, target: @org)

      as @owner
      events = assert_performed_audit_entries(count: 2, only: EVENTS) do
        assert_difference -> { SecurityConfiguration.count }, 0 do
          assert_difference -> { SecurityConfigurationDefault.count }, -1 do

            put "/organizations/#{@org.display_login}/settings/security_products/configurations/#{config.id}", params: {
              security_configuration: {
                name: config.name,
                description: config.description,
                enable_ghas: config.enable_ghas,
                private_vulnerability_reporting: config.private_vulnerability_reporting,
                dependency_graph: config.dependency_graph,
                dependabot_alerts: config.dependabot_alerts,
                dependabot_security_updates: config.dependabot_security_updates,
                code_scanning: config.code_scanning,
                secret_scanning: config.secret_scanning,
                secret_scanning_push_protection: config.secret_scanning_push_protection,
              },
              default_for_new_public_repos: false,
              default_for_new_private_repos: false,
              enforcement: :not_enforced
            }, as: :json
          end
        end
      end

      event = events.find { |e| e[:action] == "security_configuration_default.delete" }

      assert_equal "security_configuration_default.delete", event[:action]
      assert_equal @owner.display_login, event[:actor]
      assert_equal @org.display_login, event[:target]
      assert_equal config.name, event[:security_configuration_name]
    end

    context "unbundled SKUs" do
      test "allows you to update SKU specific attributes" do
        setup_entity_as_volume_unbundled(@business)

        config = create(:unbundled_security_configuration, target: @org)
        assert config.code_security_sku_enabled?, "Expected Code Security SKU to be enabled for test setup."

        assert_no_difference -> { SecurityConfiguration.count } do
          as @owner
          put "/organizations/#{@org.display_login}/settings/security_products/configurations/#{config.id}", params: {
            security_configuration: {
              name: "Updated config",
              code_security_sku_enabled: false,
              code_scanning: "disabled",
              code_scanning_delegated_alert_dismissal: "disabled",
            }
          }, as: :json

          assert_response :ok
        end

        config.reload
        assert_equal "Updated config", config.name
        refute config.code_security_sku_enabled, "Expected code security SKU to be disabled"
        assert config.code_scanning_disabled?, "Expected code scanning to be disabled"
        assert config.code_scanning_delegated_alert_dismissal_disabled?, "Expected code scanning delegated alert dismissal to be disabled"
      end
    end
  end

  context "#show" do
    test "renders the github recommended configuration", skip_enterprise: true do
      as @owner
      get "/organizations/#{@org.display_login}/settings/security_products/configurations/view/#{@gh_config.id}"

      assert_response :ok
      assert_react_payload_equal :organization, @org.display_login
      expected_payload = {
        "id" => T.must(SecurityConfiguration.github_recommended_configuration).id,
        "name" => T.must(SecurityConfiguration.github_recommended_configuration).name,
        "description" => T.must(SecurityConfiguration.github_recommended_configuration).description,
        "default_for_new_public_repos" => false,
        "default_for_new_private_repos" => false,
        "enforcement" => "not_enforced",
        "target_type" => "global",
        "private_vulnerability_reporting" => GitHub.private_vulnerability_reporting_enabled? ? "enabled" : "disabled",
        "dependency_graph" => "enabled",
        "dependency_graph_autosubmit_action" => "not_set",
        "dependency_graph_autosubmit_action_options" => { "labeled_runners" => false },
        "dependabot_alerts" => "enabled",
        "dependabot_security_updates" => "not_set",
        "code_scanning" => "enabled",
        "code_scanning_delegated_alert_dismissal" => "not_set",
        "code_scanning_options" => { "runner_type" => "not_set", "runner_label" => nil },
        "secret_scanning" => "enabled",
        "secret_scanning_push_protection" => "enabled",
        "secret_scanning_non_provider_patterns" => "enabled",
        "secret_scanning_validity_checks" => GitHub.secret_scanning_validity_checks_available_on_instance? ? "enabled" : "disabled",
        "secret_scanning_delegated_bypass" => "not_set",
        "secret_scanning_generic_secrets" => "not_set",
        "secret_scanning_delegated_alert_dismissal" => "not_set",
        "enable_ghas" => true,
        "code_security_sku_enabled" => false,
        "secret_protection_sku_enabled" => false,
        "repositories_count" => 0
      }

      assert_react_payload_equal(:security_configuration, expected_payload)
    end

    test "renders the github recommended configuration for an unbundled org", skip_enterprise: true do
      setup_entity_as_volume_unbundled(@business)

      as @owner
      get "/organizations/#{@org.display_login}/settings/security_products/configurations/view/#{@gh_config.id}"

      assert_response :ok
      assert_react_payload_equal :organization, @org.display_login
      expected_payload = {
        "id" => T.must(SecurityConfiguration.github_recommended_configuration).id,
        "name" => T.must(SecurityConfiguration.github_recommended_configuration).name,
        "description" => "Suggested settings for Secret Protection and Code Security, managed by GitHub.",
        "default_for_new_public_repos" => false,
        "default_for_new_private_repos" => false,
        "enforcement" => "not_enforced",
        "target_type" => "global",
        "private_vulnerability_reporting" => GitHub.private_vulnerability_reporting_enabled? ? "enabled" : "disabled",
        "dependency_graph" => "enabled",
        "dependency_graph_autosubmit_action" => "not_set",
        "dependency_graph_autosubmit_action_options" => { "labeled_runners" => false },
        "dependabot_alerts" => "enabled",
        "dependabot_security_updates" => "not_set",
        "code_scanning" => "enabled",
        "code_scanning_delegated_alert_dismissal" => "not_set",
        "code_scanning_options" => { "runner_type" => "not_set", "runner_label" => nil },
        "secret_scanning" => "enabled",
        "secret_scanning_push_protection" => "enabled",
        "secret_scanning_non_provider_patterns" => "enabled",
        "secret_scanning_validity_checks" => GitHub.secret_scanning_validity_checks_available_on_instance? ? "enabled" : "disabled",
        "secret_scanning_delegated_bypass" => "not_set",
        "secret_scanning_generic_secrets" => "not_set",
        "secret_scanning_delegated_alert_dismissal" => "not_set",
        "enable_ghas" => false,
        "code_security_sku_enabled" => true,
        "secret_protection_sku_enabled" => true,
        "repositories_count" => 0
      }

      assert_react_payload_equal(:security_configuration, expected_payload)
    end

    test "renders the enforced github recommended configuration", skip_enterprise: true do
      create(:security_configuration_default,
        target: @org,
        default_for_new_public_repos: false,
        default_for_new_private_repos: false,
        security_configuration_id: T.must(SecurityConfiguration.github_recommended_configuration).id,
      )

      create(:security_configuration_policy,
        target: @org,
        enforcement: :enforced,
        security_configuration_id: T.must(SecurityConfiguration.github_recommended_configuration).id
      )

      as @owner
      get "/organizations/#{@org.display_login}/settings/security_products/configurations/view/#{@gh_config.id}"

      assert_response :ok
      assert_react_payload_equal :organization, @org.display_login
      expected_payload = {
        "id" => T.must(SecurityConfiguration.github_recommended_configuration).id,
        "name" => T.must(SecurityConfiguration.github_recommended_configuration).name,
        "description" => T.must(SecurityConfiguration.github_recommended_configuration).description,
        "default_for_new_public_repos" => false,
        "default_for_new_private_repos" => false,
        "enforcement" => "enforced",
        "target_type" => "global",
        "private_vulnerability_reporting" => GitHub.private_vulnerability_reporting_enabled? ? "enabled" : "disabled",
        "dependency_graph" => "enabled",
        "dependency_graph_autosubmit_action" => "not_set",
        "dependency_graph_autosubmit_action_options" => { "labeled_runners" => false },
        "dependabot_alerts" => "enabled",
        "dependabot_security_updates" => "not_set",
        "code_scanning" => "enabled",
        "code_scanning_delegated_alert_dismissal" => "not_set",
        "code_scanning_options" => { "runner_type" => "not_set", "runner_label" => nil },
        "secret_scanning" => "enabled",
        "secret_scanning_push_protection" => "enabled",
        "secret_scanning_non_provider_patterns" => "enabled",
        "secret_scanning_validity_checks" => GitHub.secret_scanning_validity_checks_available_on_instance? ? "enabled" : "disabled",
        "secret_scanning_delegated_bypass" => "not_set",
        "secret_scanning_generic_secrets" => "not_set",
        "secret_scanning_delegated_alert_dismissal" => "not_set",
        "enable_ghas" => true,
        "code_security_sku_enabled" => false,
        "secret_protection_sku_enabled" => false,
        "repositories_count" => 0
      }
      assert_react_payload_equal(:security_configuration, expected_payload)
    end

    test "renders enforced enterprise configuration" do
      custom_enterprise_config = create(:security_configuration, target: @business)

      create(:security_configuration_policy,
        target: @business,
        enforcement: :enforced,
        security_configuration_id: custom_enterprise_config.id
      )

      as @owner
      get "/organizations/#{@org.display_login}/settings/security_products/configurations/view/#{custom_enterprise_config.id}"

      assert_response :ok
      assert_react_payload_equal :organization, @org.display_login
      expected_payload = {
        "id" => custom_enterprise_config.id,
        "name" => custom_enterprise_config.name,
        "description" => custom_enterprise_config.description,
        "default_for_new_public_repos" => false,
        "default_for_new_private_repos" => false,
        "enforcement" => "enforced",
        "target_type" => "Business",
        "private_vulnerability_reporting" => GitHub.private_vulnerability_reporting_enabled? ? "enabled" : "disabled",
        "dependency_graph" => "enabled",
        "code_scanning_delegated_alert_dismissal" => "disabled",
        "dependency_graph_autosubmit_action" => "disabled",
        "dependency_graph_autosubmit_action_options" => { "labeled_runners" => false },
        "dependabot_alerts" => "enabled",
        "dependabot_security_updates" => "enabled",
        "code_scanning" => "enabled",
        "code_scanning_options" => { "runner_type" => "not_set", "runner_label" => nil },
        "secret_scanning" => "enabled",
        "secret_scanning_push_protection" => "enabled",
        "secret_scanning_delegated_bypass" => "disabled",
        "secret_scanning_delegated_alert_dismissal" => "disabled",
        "secret_scanning_non_provider_patterns" => "disabled",
        "enable_ghas" => true,
        "code_security_sku_enabled" => false,
        "secret_protection_sku_enabled" => false,
        "repositories_count" => 0
      }

      unless GitHub.enterprise?
        expected_payload["secret_scanning_validity_checks"] = "disabled"
        expected_payload["secret_scanning_generic_secrets"] = "disabled"
      end

      assert_react_payload_equal(:security_configuration, expected_payload)
    end

    test "renders an enforced enterprise configuration as not enforced at org if org changes enforcement" do
      custom_enterprise_config = create(:security_configuration, target: @business)

      create(:security_configuration_policy,
        target: @business,
        enforcement: :enforced,
        security_configuration_id: custom_enterprise_config.id
      )

      create(:security_configuration_policy,
        target: @org,
        enforcement: :not_enforced,
        security_configuration_id: custom_enterprise_config.id
      )

      as @owner
      get "/organizations/#{@org.display_login}/settings/security_products/configurations/view/#{custom_enterprise_config.id}"

      assert_response :ok
      assert_react_payload_equal :organization, @org.display_login
      expected_payload = {
        "id" => custom_enterprise_config.id,
        "name" => custom_enterprise_config.name,
        "description" => custom_enterprise_config.description,
        "default_for_new_public_repos" => false,
        "default_for_new_private_repos" => false,
        "enforcement" => "not_enforced",
        "target_type" => "Business",
        "private_vulnerability_reporting" => GitHub.private_vulnerability_reporting_enabled? ? "enabled" : "disabled",
        "dependency_graph" => "enabled",
        "dependency_graph_autosubmit_action" => "disabled",
        "dependency_graph_autosubmit_action_options" => { "labeled_runners" => false },
        "dependabot_alerts" => "enabled",
        "dependabot_security_updates" => "enabled",
        "code_scanning" => "enabled",
        "code_scanning_delegated_alert_dismissal" => "disabled",
        "code_scanning_options" => { "runner_type" => "not_set", "runner_label" => nil },
        "secret_scanning" => "enabled",
        "secret_scanning_push_protection" => "enabled",
        "secret_scanning_delegated_bypass" => "disabled",
        "secret_scanning_delegated_alert_dismissal" => "disabled",
        "secret_scanning_non_provider_patterns" => "disabled",
        "enable_ghas" => true,
        "code_security_sku_enabled" => false,
        "secret_protection_sku_enabled" => false,
        "repositories_count" => 0
      }

      unless GitHub.enterprise?
        expected_payload["secret_scanning_validity_checks"] = "disabled"
        expected_payload["secret_scanning_generic_secrets"] = "disabled"
      end

      assert_react_payload_equal(:security_configuration, expected_payload)
    end

    test "payload indicates if enablement changes are in progress" do
      Organization.any_instance.expects(:security_configurations_blocked?).returns(true)
      custom_enterprise_config = create(:security_configuration, target: @business)

      as @owner
      get "/organizations/#{@org.display_login}/settings/security_products/configurations/view/#{custom_enterprise_config.id}"

      assert_react_payload_equal :changesInProgress, { "inProgress" => true, "type" => "enablement_changes" }
    end

    test "payload indicates if a configuration is being applied" do
      Organization.any_instance.expects(:jobs_in_progress?).returns(true)
      custom_emterprise_config = create(:security_configuration, target: @business)

      as @owner
      get "/organizations/#{@org.display_login}/settings/security_products/configurations/view/#{custom_emterprise_config.id}"

      assert_react_payload_equal :changesInProgress, { "inProgress" => true, "type" => "applying_configuration" }
    end

    test "payload includes feature flag info" do
      custom_enterprise_config = create(:security_configuration, target: @business)

      as @owner
      get "/organizations/#{@org.display_login}/settings/security_products/configurations/view/#{custom_enterprise_config.id}"

      assert_response :success

      SecurityConfigurations::FeatureFlagHelper.client_feature_flags.each do |flag|
        if @org.feature_enabled?(flag)
          assert_react_feature_flag_enabled(flag)
        end
      end
    end
  end

  context "#destroy" do
    test "returns 400 if a user attempts to delete github recommended configuration", skip_enterprise: true do
      as @owner
      delete "/organizations/#{@org.display_login}/settings/security_products/configurations/#{@gh_config.id}", params: {
        security_configuration: {
          name: @gh_config.name,
        }
      }, as: :json

      assert_response :not_found
    end

    test "deletes the configuration" do
      config = create(:security_configuration, target: @org)
      as @owner
      delete "/organizations/#{@org.display_login}/settings/security_products/configurations/#{config.id}"

      assert_raises(ActiveRecord::RecordNotFound) { config.reload }
      assert_response :no_content
    end

    test "returns 422 if security configurations are being applied on the org" do
      # Pretend configurations are being applied to the org:
      job_progress_tracker = SecurityProductsEnablement::JobProgressTracker.new(@org.id)
      job_progress_tracker.start

      config = create(:security_configuration, target: @org)

      as @owner
      delete "/organizations/#{@org.display_login}/settings/security_products/configurations/#{config.id}"

      assert_response :unprocessable_entity
    end

    test "returns 422 if BlockedSettings are active for the org" do
      # Pretend configurations are being blocked:
      job_status = SecurityProductsEnablement::JobStatus.create({ id: SecurityAnalysisSettingsUpdateJob.job_id(@org, :auto_codeql_enable_all) })

      config = create(:security_configuration, target: @org)

      as @owner
      delete "/organizations/#{@org.display_login}/settings/security_products/configurations/#{config.id}"

      assert_response :unprocessable_entity
    end

    test "creates an audit log entry when deleting a configuration" do
      security_config = create(:security_configuration, target: @org)

      as @owner
      events = assert_performed_audit_entries(count: 1, only: EVENTS) do
        assert_difference -> { SecurityConfiguration.count }, -1 do
          delete "/organizations/#{@org.display_login}/settings/security_products/configurations/#{security_config.id}"
        end
      end
      event = events.sole

      assert_nil SecurityConfiguration.find_by(id: security_config.id)
      assert_equal "security_configuration.delete", event[:action]
      assert_equal @owner.display_login, event[:actor]
      assert_equal @org.display_login, event[:target]
    end
  end

  context "#repositories_count" do
    test "returns the count of repositories that have the configuration applied" do
      configuration = create(:security_configuration, target: @org)
      repo = create(:private_repository, owner: @org)

      repo_config = create(:repository_security_configuration, repository: repo, security_configuration: configuration)
      repo_config.update(state: "attached")

      as @owner
      get "/organizations/#{@org.display_login}/settings/security_products/configuration/#{configuration.id}/repositories_count"

      assert_response :ok
      assert_equal({ "repo_count" => 1 }, response.parsed_body)
    end
  end
end
