# typed: true
# frozen_string_literal: true

require "test_helper"
class Users::Settings::SecurityProductsControllerTest < GitHub::IntegrationTestCase
  include GitHub::ReactPayloadHelper
  include SecurityProductsEnablementHelpers
  include TurboghasHelpers
  include HydroMessageJobTestHelpers

  setup do
    GitHub.flipper[:user_security_configurations].enable

    if GitHub.enterprise?
      stub_security_products_manager(enabled: true)
    end

    unless GitHub.enterprise?
      GitHub.flipper[:secret_scanning_validity_checks_in_security_configurations].enable
    end
  end

  fixtures do
    @user = create(:user)
    @repo1 = create(:repository, owner: @user)
    @repo2 = create(:repository, owner: @user)
    @repo3 = create(:private_repository, owner: @user)

    @different_user = create(:user)
    @different_public_repo = create(:public_repository, owner: @different_user, force_user_owned: true)
    @different_private_repo = create(:private_repository, owner: @different_user, force_user_owned: true)

    unless GitHub.enterprise?
      @gh_config = SecurityConfiguration.github_recommended_configuration
    end
  end

  context "#index" do
    test "renders for user" do
      as @user
      get "/users/settings/security_products"

      assert_response :success
    end

    test "payload includes default values and user name and empty set of configs" do
      as @user
      get "/users/settings/security_products"

      ghr_payload = unless GitHub.enterprise?
        {
          "id" => SecurityConfiguration.github_recommended_configuration&.id,
          "name" => SecurityConfiguration.github_recommended_configuration&.name,
          "description" => SecurityConfiguration.github_recommended_configuration&.description,
          "default_for_new_public_repos" => false,
          "default_for_new_private_repos" => false,
          "enforcement" => "not_enforced",
          "enable_ghas" => true,
          "repositories_count" => 0
        }
      end

      assert_react_payload_equal :user, @user.display_login

      if GitHub.enterprise?
        assert_react_payload_nil(:githubRecommendedConfiguration)
      else
        assert_react_payload_equal :githubRecommendedConfiguration, ghr_payload
      end

      assert_react_payload_equal :customSecurityConfigurations, []

      assert_react_payload_equal :capabilities, {
        "actionsAreBilled" => !GitHub.enterprise?,
        "ghasFreeForPublicRepos" => !GitHub.enterprise?,
        "hasPublicRepos" => !TestEnv.test_in_multitenancy_mode?,
        "previewNext" => GitHub.flipper[:security_configurations_preview_next].enabled?,
      }

      assert_react_payload_equal :securityProducts, {
        "dependency_graph" => {
          "availability" => "available",
          "configurablePerRepo" => !GitHub.enterprise?
        },
        "dependency_graph_autosubmit_action" => {
          "availability" => GitHub.enterprise? ? "unavailable" : "available"
        },
        "dependabot_alerts" => {
          "availability" => "available"
        },
        "dependabot_vea" => {
          "availability" => "available"
        },
        "dependabot_updates" => {
          "availability" => "available"
        },
        "code_scanning" => {
          "availability" => "available", "onlyLabeledRunners" => GitHub.enterprise?
        },
        "secret_scanning" => {
          "availability" => "available"
        },
        "private_vulnerability_reporting" => {
          "availability" => TestEnv.test_in_multitenancy_mode? || GitHub.enterprise? ? "unavailable" : "available"
        },
      }

      assert get_react_payload_value_from_keys(%w[docsUrls createConfig]).start_with?("https://docs.github.com")
      assert get_react_payload_value_from_keys(%w[docsUrls ghasBilling]).start_with?("https://docs.github.com")
      assert get_react_payload_value_from_keys(%w[docsUrls ghasTrial]).start_with?("https://docs.github.com")
      assert get_react_payload_value_from_keys(%w[docsUrls installSecurityProducts]).start_with?("https://docs.github.com")
    end

    test "payload includes correct availability status when security products are unavailable" do
      stub_security_products_manager enabled: false

      as @user
      get "/users/settings/security_products"

      assert_react_payload_equal :user, @user.display_login

      assert_react_payload_equal :securityProducts, {
        "dependency_graph" => {
          "availability" => "unavailable",
          "configurablePerRepo" => !GitHub.enterprise?
        },
        "dependency_graph_autosubmit_action" => {
          "availability" => GitHub.enterprise? ? "unavailable" : "available"
        },
        "dependabot_alerts" => {
          "availability" => "unavailable"
        },
        "dependabot_vea" => {
          "availability" => "unavailable"
        },
        "dependabot_updates" => {
          "availability" => "unavailable"
        },
        "code_scanning" => {
          "availability" => "unavailable", "onlyLabeledRunners" => GitHub.enterprise?
        },
        "secret_scanning" => {
          "availability" => "unavailable"
        },
        "private_vulnerability_reporting" => {
          "availability" => "unavailable"
        },
      }
    end

    test "payload includes user name and repository count for GH config", skip_enterprise: true do
      repo_config = RepositorySecurityConfiguration.create!(
        security_configuration_id: T.must(SecurityConfiguration.github_recommended_configuration).id,
        state: :attached,
        organization_id: @user.id,
        repository: @repo1
      )

      as @user
      get "/users/settings/security_products"

      assert_react_payload_equal :user, @user.display_login
      assert_react_payload_equal :githubRecommendedConfiguration, {
        "id" => T.must(SecurityConfiguration.github_recommended_configuration).id,
        "name" => T.must(SecurityConfiguration.github_recommended_configuration).name,
        "description" => T.must(SecurityConfiguration.github_recommended_configuration).description,
        "default_for_new_public_repos" => false,
        "default_for_new_private_repos" => false,
        "enforcement" => "not_enforced",
        "enable_ghas" => true,
        "repositories_count" => 1
      }
      assert_react_payload_equal :customSecurityConfigurations, []
    end

    test "payload includes configurations when present" do
      config = create(:security_configuration, :default_for_new_private_repos, target: @user, name: "config1", description: "desc1")

      as @user
      get "/users/settings/security_products"

      assert_react_payload_equal :user, @user.display_login
      assert_react_payload_equal :custom_security_configurations, [{
        "id" => config.id,
        "name" => "config1",
        "description" => "desc1",
        "enable_ghas" => true,
        "repositories_count" => 0,
        "default_for_new_public_repos" => false,
        "default_for_new_private_repos" => true,
        "enforcement" => "not_enforced",
      }]
    end

    test "payload includes total repository count", skip_with_all_emus: true do
      stub_const(Settings::SecurityProducts::RepositoriesHelper, :DEFAULT_PER_PAGE, 2) do
        as @user
        get "/users/settings/security_products"
      end

      assert_react_payload_equal :totalRepositoryCount, 3
      assert_react_payload_equal :page_count, 2
      assert_react_payload_count :repositories, 3
    end

    test "payload includes repositories", skip_with_all_emus: true do
      security_config = create(:security_configuration, target: @user, name: "config1", description: "desc1")

      repo_config = RepositorySecurityConfiguration.create!(
        security_configuration_id: security_config.id,
        state: :attaching,
        organization_id: @user.id,
        repository_id: @repo1.id
      )

      SecurityProductsEnablement::JobProgressTracker.new(@user.id).start

      as @user
      get "/users/settings/security_products"

      assert_react_payload_same_elements :repositories, [
        {
          "id" => @repo2.id,
          "name" => @repo2.name,
          "visibility" => @repo2.visibility,
          "archived" => @repo2.archived?,
          "pushed_at" => @repo2.pushed_at.as_json,
          "licenses_required" => nil,
          "security_configuration" => nil,
          "security_features_enabled" => GitHub.enterprise? ? false : true, # dependency graph is not automatically enabled on enterprise
        },
        {
          "id" => @repo1.id,
          "name" => @repo1.name,
          "visibility" => @repo1.visibility,
          "archived" => @repo1.archived?,
          "pushed_at" => @repo1.pushed_at.as_json,
          "licenses_required" => nil,
          "security_configuration" => {
            "name" => security_config.name,
            "status" => repo_config.state,
            "failure_reason" => repo_config.failure_reason,
            "is_github_recommended_configuration" => false,
            "repository_security_configuration_id" => repo_config.id
          },
          "security_features_enabled" => false,
        },
        {
          "id" => @repo3.id,
          "name" => @repo3.name,
          "visibility" => @repo3.visibility,
          "archived" => @repo3.archived?,
          "pushed_at" => @repo3.pushed_at.as_json,
          "licenses_required" => nil,
          "security_configuration" => nil,
          "security_features_enabled" => false,
        },
      ]
    end
  end

  context "#new" do
    test "renders for user" do
      as @user
      get "/users/settings/security_products/configurations/new"

      assert_response :success
    end

    test "payload includes user name" do
      as @user
      get "/users/settings/security_products/configurations/new"

      assert_react_payload_equal :user, @user.display_login
    end
  end

  context "#create" do
    test "returns 201 response when a security configuration is created" do
      assert_difference -> { SecurityConfiguration.count }, 1 do
        as @user
        post "/users/settings/security_products/configurations", params: {
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
            secret_scanning_delegated_bypass: "enabled"
          }
        }, as: :json

        assert_response :created
      end

      config = T.must(SecurityConfiguration.last)
      assert_equal @user, config.target
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
    end

    test "returns 201 response when a security configuration can be created, and also set as default for new repos" do
      assert_difference -> { SecurityConfiguration.count }, 1 do
        as @user
        post "/users/settings/security_products/configurations", params: {
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
          },
          default_for_new_public_repos: true,
          default_for_new_private_repos: true
        }, as: :json

        assert_response :created
      end

      config = SecurityConfiguration.last!
      assert_equal @user, config.target

      assert_equal 1, config.security_configuration_defaults.default_for_new_public_and_private_repos.count
      assert_empty config.security_configuration_policies
    end

    test "returns 201 response when a security configuration is set as default for only private and internal repositories" do
      assert_difference -> { SecurityConfiguration.count }, 1 do
        as @user
        post "/users/settings/security_products/configurations", params: {
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
          },
          default_for_new_public_repos: false,
          default_for_new_private_repos: true,
          enforcement: :not_enforced
        }, as: :json

        assert_response :created
      end

      config = SecurityConfiguration.last!
      assert_equal @user, config.target

      assert_equal 1, config.security_configuration_defaults.count
      assert_equal 1, config.security_configuration_defaults.default_for_new_private_repos.count
      assert_empty config.security_configuration_policies
    end

    test "returns 201 response when a security configuration is enforced" do
      assert_difference -> { SecurityConfiguration.count }, 1 do
        as @user
        post "/users/settings/security_products/configurations", params: {
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
          },
          default_for_new_public_repos: false,
          default_for_new_private_repos: false,
          enforcement: :enforced
        }, as: :json

        assert_response :created
      end

      config = SecurityConfiguration.last!
      assert_equal @user, config.target

      policies = config.security_configuration_policies
      assert_equal 1, policies.count
      assert_equal 1, policies.enforced.count
    end

    test "returns 422 response when a security configuration cannot be created" do
      assert_no_changes -> { SecurityConfiguration.count } do
        as @user
        post "/users/settings/security_products/configurations", params: {
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
        as @user
        post "/users/settings/security_products/configurations", params: {
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
      as @user
      post "/users/settings/security_products/configurations"

      assert_response :unprocessable_entity
    end
  end

  context "#edit" do
    test "payload includes user name and security config" do
      config = create(:security_configuration, target: @user)
      as @user
      get "/users/settings/security_products/configurations/edit/#{config.id}"

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
        "code_scanning_options" => { "runner_type" => "not_set", "runner_label" => nil },
        "secret_scanning" => "enabled",
        "secret_scanning_push_protection" => "enabled",
        "secret_scanning_delegated_bypass" => "disabled",
        "secret_scanning_non_provider_patterns" => "disabled",
        "enable_ghas" => true,
        "repositories_count" => 0
      }

      unless GitHub.enterprise?
        expected_payload["secret_scanning_validity_checks"] = "disabled"
      end

      assert_react_payload_equal :user, @user.display_login
      assert_react_payload_equal(:security_configuration, expected_payload)
    end
  end

  context "#update" do
    test "returns 200 response when a security configuration is updated" do
      config = create(:security_configuration, target: @user)

      assert_no_difference -> { SecurityConfiguration.count } do
        as @user
        put "/users/settings/security_products/configurations/#{config.id}", params: {
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
            secret_scanning: "not_set",
            secret_scanning_push_protection: "not_set",
          }
        }, as: :json

        assert_response :ok
      end

      config.reload
      assert_equal @user, config.target
      assert_equal "config name", config.name
      assert_equal "config description", config.description
      assert config.enable_ghas?, "expected GHAS to be enabled"
      assert config.private_vulnerability_reporting_disabled?, "expected PVR to be disabled"
      assert config.dependency_graph_disabled?, "expected dependency graph to be disabled"
      assert config.dependabot_alerts_disabled?, "expected dependabot alerts to be disabled"
      assert config.dependabot_security_updates_disabled?, "expected dependabot security updates to be disabled"
      assert config.code_scanning_enabled?, "expected code scanning to be enabled"
      assert config.secret_scanning_not_set?, "expected secret scanning to be not set"
      assert config.secret_scanning_push_protection_not_set?, "expected secret scanning push protection to be not_set"
    end

    test "returns 200 response when a security configuration is set as default for new public, private and internal repositories" do
      config = create(:security_configuration, target: @user)

      assert_no_difference -> { SecurityConfiguration.count } do
        as @user
        put "/users/settings/security_products/configurations/#{config.id}", params: {
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
          },
          default_for_new_public_repos: true,
          default_for_new_private_repos: true
        }, as: :json

        assert_response :ok
      end

      assert_equal 1, config.security_configuration_defaults.default_for_new_public_and_private_repos.count
    end

    test "returns 200 response when a security configuration is set as default for only private and internal repositories" do
      config = create(:security_configuration, target: @user)

      assert_no_difference -> { SecurityConfiguration.count } do
        as @user
        put "/users/settings/security_products/configurations/#{config.id}", params: {
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
          },
          default_for_new_public_repos: false,
          default_for_new_private_repos: true
        }, as: :json

        assert_response :ok
      end

      assert_equal 1, config.security_configuration_defaults.count
      assert_equal 1, config.security_configuration_defaults.default_for_new_private_repos.count
    end

    test "updates the gh recommended configuration defaults for an org", skip_enterprise: true do
      assert_no_changes -> { @gh_config.reload } do
        as @user
        put "/users/settings/security_products/configurations/#{@gh_config.id}", params: {
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
      config_default = SecurityConfigurationDefault.where(security_configuration_id: @gh_config.id, target_id: @user.id).first
      assert config_default
      assert T.must(config_default).default_for_new_public_repos
      refute T.must(config_default).default_for_new_private_repos

      policies = @gh_config.security_configuration_policies
      assert_equal 1, policies.count
      assert_equal 1, policies.not_enforced.count
    end

    test "updates the gh recommended configuration to mark it as enforced", skip_enterprise: true do
      assert_no_changes -> { @gh_config.reload } do
        as @user
        put "/users/settings/security_products/configurations/#{@gh_config.id}", params: {
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
        as @user
        put "/users/settings/security_products/configurations/#{config.id}", params: {
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
      config = create(:security_configuration, target: @user)

      assert_no_difference -> { SecurityConfiguration.count } do
        as @user
        put "/users/settings/security_products/configurations/#{config.id}", params: {
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
      config = create(:security_configuration, target: @user)

      assert_no_difference -> { SecurityConfiguration.count } do
        as @user
        put "/users/settings/security_products/configurations/#{config.id}", params: {
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

    test "returns 422 when updating a config to use a reserved name" do
      config = create(:security_configuration, target: @user)

      as @user
      put "/users/settings/security_products/configurations/#{config.id}", params: {
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
  end

  context "#show" do
    test "renders the github recommended configuration", skip_enterprise: true do
      as @user
      get "/users/settings/security_products/configurations/view/#{@gh_config.id}"

      assert_response :ok
      assert_react_payload_equal :user, @user.display_login
      assert_react_payload_equal(:security_configuration, {
        "id" => @gh_config.id,
        "name" => @gh_config.name,
        "description" => @gh_config.description,
        "default_for_new_public_repos" => false,
        "default_for_new_private_repos" => false,
        "enforcement" => "not_enforced",
        "enable_ghas" => true,
        "repositories_count" => 0,
        "target_type" => "global",
        "private_vulnerability_reporting" => GitHub.private_vulnerability_reporting_enabled? ? "enabled" : "disabled",
        "dependency_graph" => "enabled",
        "dependency_graph_autosubmit_action" => "not_set",
        "dependency_graph_autosubmit_action_options" => { "labeled_runners" => false },
        "dependabot_alerts" => "enabled",
        "dependabot_security_updates" => "not_set",
        "code_scanning" => "enabled",
        "code_scanning_options" => { "runner_type" => "not_set", "runner_label" => nil },
        "secret_scanning" => "enabled",
        "secret_scanning_push_protection" => "enabled",
        "secret_scanning_validity_checks" => "enabled",
        "secret_scanning_delegated_bypass" => "not_set",
        "secret_scanning_non_provider_patterns" => "enabled"
      })
    end

    test "renders the enforced github recommended configuration", skip_enterprise: true do
      create(:security_configuration_default,
        target: @user,
        default_for_new_public_repos: false,
        default_for_new_private_repos: false,
        security_configuration_id: T.must(SecurityConfiguration.github_recommended_configuration).id,
      )

      create(:security_configuration_policy,
        target: @user,
        enforcement: :enforced,
        security_configuration_id: T.must(SecurityConfiguration.github_recommended_configuration).id
      )

      as @user
      get "/users/settings/security_products/configurations/view/#{@gh_config.id}"

      assert_response :ok
      assert_react_payload_equal :user, @user.display_login
      assert_react_payload_equal(:security_configuration, {
        "id" => T.must(SecurityConfiguration.github_recommended_configuration).id,
        "name" => T.must(SecurityConfiguration.github_recommended_configuration).name,
        "description" => T.must(SecurityConfiguration.github_recommended_configuration).description,
        "default_for_new_public_repos" => false,
        "default_for_new_private_repos" => false,
        "enforcement" => "enforced",
        "enable_ghas" => true,
        "repositories_count" => 0,
        "target_type" => "global",
        "private_vulnerability_reporting" => GitHub.private_vulnerability_reporting_enabled? ? "enabled" : "disabled",
        "dependency_graph" => "enabled",
        "dependency_graph_autosubmit_action" => "not_set",
        "dependency_graph_autosubmit_action_options" => { "labeled_runners" => false },
        "dependabot_alerts" => "enabled",
        "dependabot_security_updates" => "not_set",
        "code_scanning" => "enabled",
        "code_scanning_options" => { "runner_type" => "not_set", "runner_label" => nil },
        "secret_scanning" => "enabled",
        "secret_scanning_push_protection" => "enabled",
        "secret_scanning_validity_checks" => "enabled",
        "secret_scanning_delegated_bypass" => "not_set",
        "secret_scanning_non_provider_patterns" => "enabled",
      })
    end
  end

  context "#repositories_count" do
    test "returns the count of repositories that have the configuration applied" do
      configuration = create(:security_configuration, target: @user)
      repo = create(:private_repository, owner: @user)

      repo_config = RepositorySecurityConfiguration.create(
        repository: repo,
        security_configuration: configuration,
        organization_id: @user.id,
        state: "attached"
      )

      as @user
      get "/users/settings/security_products/configuration/#{configuration.id}/repositories_count"

      assert_response :ok
      assert_equal({ "repo_count" => 1 }, response.parsed_body)
    end
  end

  def stub_security_products_manager(enabled: true)
    SecurityProductsEnablement::SecurityProductsManager.any_instance.stubs(:dependency_graph_enabled?).returns(enabled)
    SecurityProductsEnablement::SecurityProductsManager.any_instance.stubs(:dependabot_alerts_enabled?).returns(enabled)
    SecurityProductsEnablement::SecurityProductsManager.any_instance.stubs(:dependabot_security_updates_enabled?).returns(enabled)
    SecurityProductsEnablement::SecurityProductsManager.any_instance.stubs(:dependabot_vea_enabled?).returns(enabled)
    SecurityProductsEnablement::SecurityProductsManager.any_instance.stubs(:code_scanning_default_setup_enabled?).returns(enabled)
    SecurityProductsEnablement::SecurityProductsManager.any_instance.stubs(:secret_scanning_enabled?).returns(enabled)
    # PVR is not in GHES
    SecurityProductsEnablement::SecurityProductsManager.any_instance.stubs(:private_vulnerability_reporting_enabled?).returns(enabled) unless GitHub.enterprise? || TestEnv.test_in_multitenancy_mode?
  end
end
