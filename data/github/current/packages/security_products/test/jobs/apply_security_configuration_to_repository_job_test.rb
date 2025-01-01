# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"
require "test_helpers/turboghas_helpers"

class ApplySecurityConfigurationToRepositoryJobTest < GitHub::TestCase
  include GitHub::LoggerHelper
  include JobTestHelper
  include TurboghasHelpers
  include HydroTestHelpers
  include HydroMessageJobTestHelpers
  include DogstatsTestHelpers
  include SecurityProductsEnablement::EnterpriseTestHelpers
  include SecurityProductsEnablementHelpers

  fixtures do
    @user = create(:verified_user)
    @business = create(:global_business) || create(:business, owners: [@user])
    setup_entity_as_bundled_ghas(@business)

    @non_ghas_business = create(:global_business) || create(:business, owners: [@user])
    @non_ghas_org = create(:organization, business: @non_ghas_business, admin: @user)
    @non_ghas_private_repo = create(:private_repository, :minimal, owner: @non_ghas_org)
    @non_ghas_public_repo = create(:public_repository, :minimal, owner: @non_ghas_org)

    @org = create(:business_plus_organization, business: @business, admin: @user)
    @another_org = create(:organization, admin: @user)
    @repo = create(:private_repository, :minimal, owner: @org)
    @public_repo = create(:public_repository, :minimal, owner: @org)
    @archived_repo = create(:archived_repository, public: false, owner: @org)
    @another_repo = create(:private_repository, :minimal, owner: @another_org)
  end

  setup do
    @custom_config = create(
      :security_configuration,
      target: @org,
      enable_ghas: true,
      dependabot_alerts: :enabled,
      dependency_graph: :enabled,
      code_scanning: :enabled,
      secret_scanning: :not_set,
      secret_scanning_push_protection: :not_set,
    )

    stub_auto_codeql
    stub_dependency_graph_autosubmit_action
  end

  # We need to test combinations of security products here and see effects on repository
  context "applies security configurations with a specifc security product features to repository" do
    test "enables dependabot alerts on a repository" do
      security_configuration = create(
        :security_configuration,
        target: @org,
        dependabot_alerts: :enabled,
        dependency_graph: :enabled,
        code_scanning: :not_set,
        secret_scanning: :not_set,
        secret_scanning_push_protection: :not_set,
      )

      repository_security_configuration = create(:repository_security_configuration, repository: @repo, security_configuration: security_configuration)

      ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @repo.id, security_configuration_id: security_configuration.id)

      assert_equal "attached", repository_security_configuration.reload.state
      assert_predicate @repo, :dependency_graph_enabled?
      assert_predicate @repo, :vulnerability_alerts_enabled?
    end

    test "enables dependency graph on a repository" do
      security_configuration = create(
        :security_configuration,
        target: @org,
        dependabot_security_updates: :disabled,
        dependabot_alerts: :disabled,
        dependency_graph: :enabled,
        code_scanning: :not_set,
        secret_scanning: :not_set,
        secret_scanning_push_protection: :not_set,
      )

      repository_security_configuration = create(:repository_security_configuration, repository: @repo, security_configuration: security_configuration)

      ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @repo.id, security_configuration_id: security_configuration.id)

      assert_equal "attached", repository_security_configuration.reload.state
      assert_predicate @repo, :dependency_graph_enabled?
    end

    context "dependency graph autosubmission action" do
      test "it enables autosubmission correctly" do
        security_configuration = create(
          :security_configuration,
          target: @org,
          dependency_graph: :enabled,
          dependency_graph_autosubmit_action: :enabled,
        )

        repository_security_configuration = create(:repository_security_configuration, repository: @repo, security_configuration: security_configuration)

        ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @repo.id, security_configuration_id: security_configuration.id)
        assert_equal "attached", repository_security_configuration.reload.state

        autosubmit = SecurityProduct::DependencyGraphAutosubmitAction.new(@repo)

        assert_predicate autosubmit, :enabled?
        refute_predicate autosubmit, :labeled_runners_enabled?
      end

      test "it enables autosubmission with labelled-runners correctly" do
        security_configuration = create(
          :security_configuration,
          target: @org,
          dependency_graph: :enabled,
          dependency_graph_autosubmit_action: :enabled,
          dependency_graph_autosubmit_action_options: { "labeled_runners" => true },
        )

        repository_security_configuration = create(:repository_security_configuration, repository: @repo, security_configuration: security_configuration)

        ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @repo.id, security_configuration_id: security_configuration.id)
        assert_equal "attached", repository_security_configuration.reload.state
        assert_predicate @repo, :dependency_graph_enabled?

        autosubmit = SecurityProduct::DependencyGraphAutosubmitAction.new(@repo)

        assert_predicate autosubmit, :enabled?
        assert_predicate autosubmit, :labeled_runners_enabled?
      end

      test "it cannot attach the configuration if actions is disabled on the repository" do
        @repo.disable_actions(actor: @user)

        security_configuration = create(
          :security_configuration,
          target: @org,
          dependency_graph: :enabled,
          dependency_graph_autosubmit_action: :enabled,
          dependency_graph_autosubmit_action_options: { "labeled_runners" => false },
        )

        repository_security_configuration = create(:repository_security_configuration, repository: @repo, security_configuration: security_configuration)

        ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @repo.id, security_configuration_id: security_configuration.id)
        assert_equal "failed", repository_security_configuration.reload.state
        assert_equal "Automatic dependency submission can only be enabled if Actions is enabled. GitHub Actions is disabled on this repository, please enable it.", repository_security_configuration.failure_reason

        autosubmit = SecurityProduct::DependencyGraphAutosubmitAction.new(@repo)

        refute_predicate autosubmit, :enabled?
        refute_predicate autosubmit, :labeled_runners_enabled?
      end

      test "it cannot attach a configuration using labelled runners if none are available for the repository" do
        stub_dependency_graph_autosubmit_action(labelled_runners_available: false)
        security_configuration = create(
          :security_configuration,
          target: @org,
          dependency_graph: :enabled,
          dependency_graph_autosubmit_action: :enabled,
          dependency_graph_autosubmit_action_options: { "labeled_runners" => true },
        )

        repository_security_configuration = create(:repository_security_configuration, repository: @repo, security_configuration: security_configuration)

        ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @repo.id, security_configuration_id: security_configuration.id)
        assert_equal "failed", repository_security_configuration.reload.state
        assert_equal "Automatic dependency submission can only be enabled if runners with label dependency-submission are assigned to this repository.", repository_security_configuration.failure_reason

        autosubmit = SecurityProduct::DependencyGraphAutosubmitAction.new(@repo)

        refute_predicate autosubmit, :enabled?
        refute_predicate autosubmit, :labeled_runners_enabled?
      end
    end

    test "enables dependabot updates on a repository" do
      security_configuration = create(
        :security_configuration,
        target: @org,
        dependabot_alerts: :enabled,
        dependency_graph: :enabled,
        dependabot_security_updates: :enabled,
        code_scanning: :not_set,
        secret_scanning: :not_set,
        secret_scanning_push_protection: :not_set,
      )

      repository_security_configuration = create(:repository_security_configuration, repository: @repo, security_configuration: security_configuration)

      ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @repo.id, security_configuration_id: security_configuration.id)

      assert_equal "attached", repository_security_configuration.reload.state
      assert_predicate @repo, :dependency_graph_enabled?
      assert_predicate @repo, :vulnerability_alerts_enabled?
      assert_predicate @repo, :vulnerability_updates_enabled?
    end

    test "enables advanced security on a repository" do
      security_configuration = create(
        :security_configuration,
        :not_set,
        target: @org,
        enable_ghas: true,
      )

      repository_security_configuration = create(:repository_security_configuration, repository: @repo, security_configuration: security_configuration)

      ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @repo.id, security_configuration_id: security_configuration.id)

      assert_equal "attached", repository_security_configuration.reload.state
      assert_predicate @repo, :advanced_security_enabled?
    end

    test "enables secret scanning on a repository" do
      security_configuration = create(
        :security_configuration,
        :not_set,
        target: @org,
        secret_scanning: :enabled,
        enable_ghas: true,
      )

      repository_security_configuration = create(:repository_security_configuration, repository: @repo, security_configuration: security_configuration)

      ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @repo.id, security_configuration_id: security_configuration.id)

      assert_equal "attached", repository_security_configuration.reload.state
      assert_predicate @repo, :advanced_security_enabled?
      assert SecretScanning::Features::Repo::TokenScanning.new(@repo).enabled?
    end

    test "enables secret scanning non provider patterns on a repository" do
      SecretScanning::Features::Repo::TokenScanning.new(@repo).disable(actor: @user) # even if token scanning is disabled before, npp and ts should be enabled when applying a security configuration
      security_configuration = create(
        :security_configuration,
        :not_set,
        target: @org,
        secret_scanning: :enabled,
        secret_scanning_non_provider_patterns: :enabled,
        secret_scanning_push_protection: :not_set,
        enable_ghas: true,
      )

      repository_security_configuration = create(:repository_security_configuration, repository: @repo, security_configuration: security_configuration)

      ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @repo.id, security_configuration_id: security_configuration.id)

      assert_equal "attached", repository_security_configuration.reload.state
      assert_predicate @repo, :advanced_security_enabled?
      assert SecretScanning::Features::Repo::LowerConfidencePatterns.new(@repo).enabled?
    end

    test "enables secret scanning delegated alert closures on a repository" do
      SecretScanning::Features::Org::DelegatedClosures.any_instance.stubs(:feature_available?).returns(true)
      SecretScanning::Features::Repo::DelegatedClosures.any_instance.stubs(:feature_available?).returns(true)
      SecretScanning::Features::Repo::TokenScanning.new(@repo).disable(actor: @user)
      security_configuration = create(
        :security_configuration,
        :not_set,
        target: @org,
        secret_scanning: :enabled,
        secret_scanning_delegated_alert_dismissal: :enabled,
        enable_ghas: true,
      )
      repository_security_configuration = create(:repository_security_configuration, repository: @repo, security_configuration: security_configuration)

      ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @repo.id, security_configuration_id: security_configuration.id)

      assert_equal "attached", repository_security_configuration.reload.state
      assert_predicate @repo, :advanced_security_enabled?
      assert SecretScanning::Features::Repo::DelegatedClosures.new(@repo).enabled?
    end

    test "enables secret scanning push protection on a repository" do
      security_configuration = create(
        :security_configuration,
        :not_set,
        target: @org,
        secret_scanning: :enabled,
        secret_scanning_push_protection: :enabled,
        enable_ghas: true,
      )

      repository_security_configuration = create(:repository_security_configuration, repository: @repo, security_configuration: security_configuration)

      ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @repo.id, security_configuration_id: security_configuration.id)

      assert_equal "attached", repository_security_configuration.reload.state
      assert_predicate @repo, :advanced_security_enabled?
      assert @repo.security_feature_configured?(:SECRET_SCANNING_PUSH_PROTECTION)
    end

    test "enables secret scanning push protection and delegated bypass on a repository being imported" do
      @repo.importing_started!

      security_configuration = create(
        :security_configuration,
        :not_set,
        target: @org,
        secret_scanning: :enabled,
        secret_scanning_push_protection: :enabled,
        secret_scanning_delegated_bypass: :enabled,
        enable_ghas: true,
      )

      repository_security_configuration = create(:repository_security_configuration, repository: @repo, security_configuration: security_configuration)

      ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @repo.id, security_configuration_id: security_configuration.id)

      @repo.importing_stopped!

      assert_equal "attached", repository_security_configuration.reload.state
      assert_predicate @repo, :advanced_security_enabled?
      assert_equal true, SecretScanning::Features::Repo::PushProtection.new(@repo).enabled?
      assert_equal true, SecretScanning::Features::Repo::DelegatedBypass.new(@repo).enabled?
    end

    test "enables code scanning on a repository" do
      security_configuration = create(
        :security_configuration,
        :not_set,
        target: @org,
        code_scanning: :enabled,
        secret_scanning: :enabled,
        enable_ghas: true,
      )

      repository_security_configuration = create(:repository_security_configuration, repository: @repo, security_configuration: security_configuration)

      expects_auto_codeql_enabled
      ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @repo.id, security_configuration_id: security_configuration.id)

      assert_equal "attached", repository_security_configuration.reload.state
      assert_predicate @repo, :advanced_security_enabled?
      assert @repo, :code_scanning_enabled?
    end

    test "enables code scanning with runner labels on a repository" do
      security_configuration = create(
        :security_configuration,
        :not_set,
        target: @org,
        code_scanning: :enabled,
        code_scanning_options: { runner_type: "labeled", runner_label: "custom-runner" },
        secret_scanning: :enabled,
        enable_ghas: true,
      )

      repository_security_configuration = create(:repository_security_configuration, repository: @repo, security_configuration: security_configuration)

      CodeScanning::AutoCodeql.any_instance.expects(:enabled?).once.returns(false)
      CodeScanning::AutoCodeql.any_instance.expects(:on_enable).with do |args|
        args[:options][:runner_label] == "custom-runner" && args[:options][:runner_type] == "labeled"
      end.once.returns(SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.empty, nil))

      ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @repo.id, security_configuration_id: security_configuration.id)

      assert_equal "attached", repository_security_configuration.reload.state
      assert_predicate @repo, :advanced_security_enabled?
      assert @repo, :code_scanning_enabled?
    end

    test "updates code scanning with runner labels on a repository" do
      security_configuration = create(
        :security_configuration,
        :not_set,
        target: @org,
        code_scanning: :enabled,
        code_scanning_options: { runner_type: "labeled", runner_label: "other-custom-runner" },
        enable_ghas: true,
      )

      repository_security_configuration = create(
        :repository_security_configuration,
        repository: @repo,
        security_configuration: security_configuration,
        state: "attached",
      )

      expects_auto_codeql_enabled
      CodeScanning::AutoCodeql.any_instance.unstub(:on_enable)

      body_params_matcher = lambda do |actual, _|
        actual_body = Turboscan::Proto::UpdateRequest.decode_json(actual.body)
        actual_body.runner_type == :RUNNER_TYPE_LABELED && actual_body.runner_label == "other-custom-runner"
      end

      VCR.use_cassette("code-scanning/managed-analyses-update", persist_with: :turboscan, match_requests_on: [:method, :uri, body_params_matcher]) do
        VCR.use_cassette("code-scanning/get-managed-analysis-info-runner-label-custom", persist_with: :turboscan) do
          ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @repo.id, security_configuration_id: security_configuration.id)
        end
      end

      assert_equal "attached", repository_security_configuration.reload.state
      assert_predicate @repo, :advanced_security_enabled?
      assert @repo, :code_scanning_enabled?
    end

    test "applies configuration with DG disabled setting for a public repo as DG enabled" do
      repo = create(:public_repository, owner: @org)

      security_configuration = create(
        :security_configuration,
        target: @org,
        dependabot_security_updates: :disabled,
        dependabot_alerts: :disabled,
        dependency_graph: :disabled,
        code_scanning: :not_set,
        secret_scanning: :not_set,
        secret_scanning_push_protection: :not_set,
      )

      repository_security_configuration = create(:repository_security_configuration, repository: repo, security_configuration: security_configuration)

      ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: repo.id, security_configuration_id: security_configuration.id)

      assert_equal "attached", repository_security_configuration.reload.state
      assert_predicate repo, :dependency_graph_enabled?
    end

    context "dotcom only features", skip_enterprise: true do
      test "enables private vulnerability alerting on a repository" do
        # PVR only exists on public repos
        repo = create(:repository, owner: @org)

        security_configuration = create(
          :security_configuration,
          target: @org,
          private_vulnerability_reporting: :enabled,
          dependabot_security_updates: :not_set,
          dependabot_alerts: :not_set,
          dependency_graph: :not_set,
          code_scanning: :not_set,
          secret_scanning: :not_set,
          secret_scanning_push_protection: :not_set,
          enable_ghas: true,
        )

        repository_security_configuration = create(:repository_security_configuration, repository: repo, security_configuration: security_configuration)

        ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: repo.id, security_configuration_id: security_configuration.id)

        assert_equal "attached", repository_security_configuration.reload.state
        assert_predicate repo, :private_vulnerability_reporting_enabled?
      end

      test "enables secret scanning validity check on a repository" do
        security_configuration = create(
          :security_configuration,
          :not_set,
          target: @org,
          secret_scanning: :enabled,
          secret_scanning_validity_checks: :enabled,
          secret_scanning_push_protection: :not_set,
          enable_ghas: true,
        )

        repository_security_configuration = create(:repository_security_configuration, repository: @repo, security_configuration: security_configuration)

        ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @repo.id, security_configuration_id: security_configuration.id)

        assert_equal "attached", repository_security_configuration.reload.state
        assert_predicate @repo, :advanced_security_enabled?
        assert SecretScanning::Features::Repo::ValidityChecks.new(@repo).enabled?
      end

      test "does not enable secret scanning non provider patterns on a non ghas repository" do
        security_configuration = create(
          :security_configuration,
          :not_set,
          target: @non_ghas_org,
          secret_scanning: :enabled,
          secret_scanning_non_provider_patterns: :enabled,
          secret_scanning_push_protection: :not_set,
          enable_ghas: true,
        )

        public_repository_security_configuration = create(:repository_security_configuration, repository: @non_ghas_public_repo, security_configuration: security_configuration)
        private_repository_security_configuration = create(:repository_security_configuration, repository: @non_ghas_private_repo, security_configuration: security_configuration)

        ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @non_ghas_public_repo.id, security_configuration_id: security_configuration.id)

        assert_equal "attached", public_repository_security_configuration.reload.state # skip enabling npp for public non ghas repos
        refute_predicate @non_ghas_public_repo, :advanced_security_enabled?
        refute SecretScanning::Features::Repo::LowerConfidencePatterns.new(@non_ghas_public_repo).enabled?

        ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @non_ghas_private_repo.id, security_configuration_id: security_configuration.id)

        assert_equal "failed", private_repository_security_configuration.reload.state # private non ghas repos cant enable secret scanning or npp
        refute_predicate @non_ghas_private_repo, :advanced_security_enabled?
        refute SecretScanning::Features::Repo::LowerConfidencePatterns.new(@non_ghas_private_repo).enabled?
      end

      test "does not enable validity checks on a non ghas repository" do
        security_configuration = create(
          :security_configuration,
          :not_set,
          target: @non_ghas_org,
          secret_scanning: :enabled,
          secret_scanning_validity_checks: :enabled,
          enable_ghas: true,
        )

        public_repository_security_configuration = create(:repository_security_configuration, repository: @non_ghas_public_repo, security_configuration: security_configuration)
        private_repository_security_configuration = create(:repository_security_configuration, repository: @non_ghas_private_repo, security_configuration: security_configuration)

        ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @non_ghas_public_repo.id, security_configuration_id: security_configuration.id)

        assert_equal "attached", public_repository_security_configuration.reload.state # skip enabling validity checks for public non ghas repos
        refute_predicate @non_ghas_public_repo, :advanced_security_enabled?
        refute SecretScanning::Features::Repo::ValidityChecks.new(@non_ghas_public_repo).enabled?

        ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @non_ghas_private_repo.id, security_configuration_id: security_configuration.id)

        assert_equal "failed", private_repository_security_configuration.reload.state # private non ghas repos cant enable secret scanning or validity checks
        refute_predicate @non_ghas_private_repo, :advanced_security_enabled?
        refute SecretScanning::Features::Repo::ValidityChecks.new(@non_ghas_private_repo).enabled?
      end
    end

    context "grouped security updates" do
      test "enables grouped security updates on a repository" do
        @org.enable_vulnerability_updates_grouping_for_new_repos(actor: @user)

        security_configuration = create(
          :security_configuration,
          target: @org,
          dependabot_security_updates: :enabled,
          dependabot_alerts: :enabled,
          dependency_graph: :enabled,
          code_scanning: :not_set,
          secret_scanning: :not_set,
          secret_scanning_push_protection: :not_set,
          enable_ghas: true,
        )
        repository_security_configuration = create(:repository_security_configuration, repository: @repo, security_configuration: security_configuration)

        ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @repo.id, security_configuration_id: security_configuration.id)

        assert_predicate @repo, :vulnerability_updates_enabled?
        assert_predicate @repo, :vulnerability_updates_grouping_enabled?
      end

      test "does not enable grouped security updates when security updates are not enabled" do
        @org.enable_vulnerability_updates_grouping_for_new_repos(actor: @user)

        security_configuration = create(
          :security_configuration,
          target: @org,
          dependabot_security_updates: :not_set,
          dependabot_alerts: :enabled,
          dependency_graph: :enabled,
          code_scanning: :not_set,
          secret_scanning: :not_set,
          secret_scanning_push_protection: :not_set,
          enable_ghas: true,
        )
        repository_security_configuration = create(:repository_security_configuration, repository: @repo, security_configuration: security_configuration)

        ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @repo.id, security_configuration_id: security_configuration.id)

        refute_predicate @repo, :vulnerability_updates_enabled?
        refute_predicate @repo, :vulnerability_updates_grouping_enabled?
      end
    end

    context "GitHub recommended configuration", skip_enterprise: true do
      test "applies the configuration to a repository" do
        security_configuration = T.must(SecurityConfiguration.github_recommended_configuration)
        repository_security_configuration = create(:repository_security_configuration, repository: @repo, security_configuration: security_configuration)

        expects_auto_codeql_enabled
        result = T.unsafe(ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @repo.id, security_configuration_id: security_configuration.id))

        # if this job run fails, it will return an exception - let's raise it so we can debug
        raise result if result.is_a?(Exception)

        assert_equal "attached", repository_security_configuration.reload.state
        assert_predicate @repo, :dependency_graph_enabled?
        assert_predicate @repo, :vulnerability_alerts_enabled?
        refute_predicate @repo, :vulnerability_updates_enabled?
        assert_equal true, SecretScanning::Features::Repo::TokenScanning.new(@repo).enabled?, "expected Secret Scanning to be enabled"
        assert_equal true, SecretScanning::Features::Repo::PushProtection.new(@repo).enabled?, "expected Push Protection to be enabled"
      end

      test "enables the Dependabot default rule" do
        security_configuration = T.must(SecurityConfiguration.github_recommended_configuration)
        repository_security_configuration = create(:repository_security_configuration, repository: @repo, security_configuration: security_configuration)

        expects_auto_codeql_enabled
        ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @repo.id, security_configuration_id: security_configuration.id)

        assert_predicate @repo, :vulnerability_alerts_enabled?
        assert_equal true, RepositoryVulnerabilityAlertRules.new(repository: @repo).default_rule_enabled?, "expected the Dependabot default rule to be enabled"
      end
    end

    context "applying default settings" do
      test "applies the default settings that are not part of configurations when a new repository is created" do
        enable_feature_flag(:dependabot_on_actions)
        enable_feature_flag(:dependabot_self_hosted)
        enable_feature_flag(:dependabot_autofix)
        enable_feature_flag(:innersource_advisories)
        enable_feature_flag(:private_advisories_disabled)

        security_configuration = create(
          :security_configuration,
          target: @org,
          dependabot_security_updates: :enabled,
          dependabot_alerts: :enabled,
          dependency_graph: :enabled,
          code_scanning: :not_set,
          secret_scanning: :not_set,
          secret_scanning_push_protection: :not_set,
          enable_ghas: true,
        )

        @org.enable_vulnerability_updates_grouping_for_new_repos(actor: @user)
        @org.enable_dependabot_on_actions_for_new_repos(actor: @user)
        @org.enable_dependabot_self_hosted_for_new_repos(actor: @user)
        @org.enable_dependabot_autofix_for_new_repos(actor: @user)
        @org.enable_innersource_advisories_for_new_repos(actor: @user) unless GitHub.enterprise? # not supported on GHES

        repository_security_configuration = create(:repository_security_configuration, repository: @repo, security_configuration: security_configuration)

        ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @repo.id, security_configuration_id: security_configuration.id, reason: :repo_creation)

        assert_predicate @repo, :vulnerability_updates_grouping_enabled?
        assert_predicate @repo, :dependabot_on_actions_enabled?
        assert_predicate @repo, :dependabot_self_hosted_enabled?
        assert_predicate @repo, :dependabot_autofix_enabled?
        assert_predicate @repo, :innersource_advisories_enabled? unless GitHub.enterprise? # not supported on GHES
      end
    end

    context "archived repository" do
      test "enables only secret scanning and some of its sub features" do
        security_configuration = create(
          :security_configuration,
          target: @org,
          private_vulnerability_reporting: :disabled,
          dependabot_security_updates: :not_set,
          dependabot_alerts: :enabled,
          dependency_graph: :enabled,
          code_scanning: :not_set,
          secret_scanning: :enabled,
          secret_scanning_non_provider_patterns: :enabled,
          secret_scanning_push_protection: :enabled,
          secret_scanning_delegated_bypass: :enabled,
          secret_scanning_validity_checks: GitHub.secret_scanning_validity_checks_available_on_instance? ? :enabled : :disabled,
          enable_ghas: true,
        )

        repository_security_configuration = create(:repository_security_configuration, repository: @archived_repo, security_configuration: security_configuration)

        ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @archived_repo.id, security_configuration_id: security_configuration.id)

        # Configuration should be considered as attached even though it's not fully applied
        assert_equal "attached", repository_security_configuration.reload.state

        assert_dogstats_increment("apply_security_configuration_to_repository_job.on_archived_repository", tags: ["state:attached"])

        # Secret scanning alerts and validity checks are available on archived repos
        assert SecretScanning::Features::Repo::TokenScanning.new(@archived_repo).enabled?
        assert SecretScanning::Features::Repo::LowerConfidencePatterns.new(@archived_repo).enabled?
        assert SecretScanning::Features::Repo::ValidityChecks.new(@archived_repo).enabled? unless GitHub.enterprise?

        # Push protection and Delegated bypass are not available on archived repos
        refute SecretScanning::Features::Repo::PushProtection.new(@archived_repo).enabled?
        refute SecretScanning::Features::Repo::DelegatedBypass.new(@archived_repo).enabled?

        refute @archived_repo.advanced_security_enabled?
        refute @archived_repo.dependency_graph_enabled? unless GitHub.enterprise?
        refute @archived_repo.vulnerability_alerts_enabled?
        refute @archived_repo.vulnerability_updates_enabled?
        refute @archived_repo.vulnerability_updates_grouping_enabled?
        refute @archived_repo.private_vulnerability_reporting_enabled?
        refute @archived_repo.code_scanning_enabled?
      end

      test "does not enable secret scanning and its sub features if they are not enabled in config" do
        security_configuration = create(
          :security_configuration,
          target: @org,
          private_vulnerability_reporting: :disabled,
          dependabot_security_updates: :not_set,
          dependabot_alerts: :not_set,
          dependency_graph: :not_set,
          code_scanning: :disabled,
          secret_scanning: :disabled,
          secret_scanning_non_provider_patterns: :disabled,
          secret_scanning_push_protection: :disabled,
          secret_scanning_validity_checks: :disabled,
          enable_ghas: true,
        )

        repository_security_configuration = create(:repository_security_configuration, repository: @archived_repo, security_configuration: security_configuration)

        ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @archived_repo.id, security_configuration_id: security_configuration.id)
        assert_equal "attached", repository_security_configuration.reload.state

        assert_dogstats_increment("apply_security_configuration_to_repository_job.on_archived_repository", tags: ["state:attached"])

        refute SecretScanning::Features::Repo::TokenScanning.new(@archived_repo).enabled?
        refute SecretScanning::Features::Repo::LowerConfidencePatterns.new(@archived_repo).enabled?
        refute SecretScanning::Features::Repo::ValidityChecks.new(@archived_repo).enabled?
        refute SecretScanning::Features::Repo::PushProtection.new(@archived_repo).enabled?
        refute @archived_repo.advanced_security_enabled?
        refute @archived_repo.dependency_graph_enabled? unless GitHub.enterprise?
        refute @archived_repo.vulnerability_alerts_enabled?
        refute @archived_repo.vulnerability_updates_enabled?
        refute @archived_repo.vulnerability_updates_grouping_enabled?
        refute @archived_repo.private_vulnerability_reporting_enabled?
        refute @archived_repo.code_scanning_enabled?
      end
    end
  end

  context "GHES testing", enterprise_only: true do
    test "repo attaches when the security configuration has an uninstalled security product" do
      security_configuration = create(:security_configuration, target: @org)

      # uninstall DG
      stub_dependency_graph_and_dependents(false)

      repository_security_configuration = create(:repository_security_configuration, repository: @repo, security_configuration: security_configuration)

      ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @repo.id, security_configuration_id: security_configuration.id)

      assert_equal "attached", repository_security_configuration.reload.state
      refute_predicate @repo, :vulnerability_alerts_enabled?
      refute_predicate @repo, :dependency_graph_enabled?
      assert_predicate @repo, :code_scanning_enabled?
    end

    test "enables advanced security on a public repository in GHES" do
      security_configuration = create(:security_configuration, target: @org, enable_ghas: true)

      repository_security_configuration = create(:repository_security_configuration, repository: @public_repo, security_configuration: security_configuration)

      ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @public_repo.id, security_configuration_id: security_configuration.id)

      assert_equal "attached", repository_security_configuration.reload.state
      assert_predicate @public_repo, :advanced_security_enabled?
    end
  end

  test "enforces a security configuration on a repository" do
    security_configuration = create(
      :security_configuration,
      target: @org,
      dependabot_alerts: :not_set,
      dependabot_security_updates: :not_set,
      dependency_graph: :not_set,
      code_scanning: :not_set,
      secret_scanning: :enabled,
      secret_scanning_push_protection: :not_set,
      enable_ghas: true,
    )
    create(:security_configuration_policy, :enforced, security_configuration:, target: @org)

    repository_security_configuration = create(:repository_security_configuration, repository: @repo, security_configuration: security_configuration)

    assert_changes -> { repository_security_configuration.reload.state }, from: "attaching", to: "enforced" do
      ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @repo.id, security_configuration_id: security_configuration.id)
    end

    assert_predicate @repo, :advanced_security_enabled?
    assert_predicate SecretScanning::Features::Repo::TokenScanning.new(@repo), :enabled?
  end

  context "retry conditions" do
    test "retries on dirty exit" do
      assert_retry_on_dirty_exit job: ApplySecurityConfigurationToRepositoryJob, args: [{ actor_id: @user.id, repository_id: @repo.id, security_configuration_id: 0 }]
    end

    test "retries on recoverable exceptions" do
      assert_retry_on_recoverable_exceptions job: ApplySecurityConfigurationToRepositoryJob, args: [{ actor_id: @user.id, repository_id: @repo.id, security_configuration_id: 0 }]
    end

    test "marks the repository security configuration as failed when the job permanently fails" do
      security_configuration = create(:security_configuration, target: @org)
      repository_security_configuration = create(:repository_security_configuration, repository: @repo, security_configuration:, state: "attaching")

      SecurityProduct::ServiceManager.any_instance.expects(:toggle_services_with_form_inputs).raises(StandardError.new("Something went wrong"))

      assert_raises(StandardError) do
        ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @repo.id, security_configuration_id: security_configuration.id)
      end

      assert_equal "failed", repository_security_configuration.reload.state
    end

    test "retries when a RetryableError is raised" do
      retryable_error_classes = ApplySecurityConfigurationToRepositoryJob::RetryableError.subclasses
      refute_empty retryable_error_classes

      retryable_error_classes.each do |retryable_error_class|
        assert_retry_on_error retryable_error_class,
          ApplySecurityConfigurationToRepositoryJob,
          [{ actor_id: @user.id, repository_id: @repo.id, security_configuration_id: 0 }]
      end
    end

    test "does not retry when a FatalError is raised" do
      fatal_error_classes = [ApplySecurityConfigurationToRepositoryJob::SecurityConfigurationOwnerMismatch, ApplySecurityConfigurationToRepositoryJob::RepositoryDeleted]
      refute_empty fatal_error_classes

      fatal_error_classes.each do |fatal_error_class|
        ApplySecurityConfigurationToRepositoryJob.any_instance.stubs(:perform).raises(fatal_error_class, "boom")

        assert_no_enqueued_jobs do
          ApplySecurityConfigurationToRepositoryJob.perform_now(
            actor_id: @user.id,
            repository_id: @repo.id,
            security_configuration_id: @custom_config.id
          )
        end
      end
    end

    test "does not retry when RepositoryArchived (FatalError) is raised" do
      ApplySecurityConfigurationToRepositoryJob.any_instance.stubs(:perform).raises(ApplySecurityConfigurationToRepositoryJob::RepositoryArchived, "boom")

      assert_no_enqueued_jobs do
        ApplySecurityConfigurationToRepositoryJob.perform_now(
          actor_id: @user.id,
          repository_id: @repo.id,
          security_configuration_id: @custom_config.id
        )
      end
    end

    test "marks the RepositorySecurityConfiguration as failed when a FatalError is raised" do
      repository_security_configuration = create(:repository_security_configuration,
        repository: @repo,
        state: "attaching",
        security_configuration: @custom_config,
      )

      ApplySecurityConfigurationToRepositoryJob.any_instance.stubs(:perform)
        .raises(ApplySecurityConfigurationToRepositoryJob::FatalError, "boom")

      ApplySecurityConfigurationToRepositoryJob.perform_now(
        actor_id: @user.id,
        repository_id: @repo.id,
        security_configuration_id: @custom_config.id
      )

      assert_equal "failed", repository_security_configuration.reload.state
    end

    test "discards job when repository is soft deleted" do
      deleted_repo = create(:deleted_repository, owner: @org)

      repository_security_configuration = create(:repository_security_configuration,
        repository: deleted_repo,
        state: "attaching",
        security_configuration: @custom_config,
      )

      assert_nothing_raised do
        assert_no_enqueued_jobs only: ApplySecurityConfigurationToRepositoryJob do
          ApplySecurityConfigurationToRepositoryJob.perform_now(
            actor_id: @user.id,
            repository_id: deleted_repo.id,
            security_configuration_id: @custom_config.id
          )
        end
      end
    end

    test "marks the RepositorySecurityConfiguration as failed when a RetryableError is raised too many times" do
      repository_security_configuration = create(:repository_security_configuration,
        repository: @repo,
        state: "attaching",
        security_configuration: @custom_config,
      )

      ApplySecurityConfigurationToRepositoryJob.perform_now(
        actor_id: 0,
        repository_id: @repo.id,
        security_configuration_id: @custom_config.id
      )

      assert_raises(ApplySecurityConfigurationToRepositoryJob::ActorNotFound) do
        5.times do
          perform_enqueued_jobs only: [ApplySecurityConfigurationToRepositoryJob]
        end
      end

      repository_security_configuration.reload

      assert_equal "failed", repository_security_configuration.state
      assert_equal "actor_not_found", repository_security_configuration.failure_reason
    end

    test "retries when the repository is not found" do
      ApplySecurityConfigurationToRepositoryJob.any_instance.stubs(:repository).returns(nil)

      args = { actor_id: @user.id, repository_id: @repo.id, security_configuration_id: @custom_config.id }
      assert_enqueued_with(job: ApplySecurityConfigurationToRepositoryJob, args: [args]) do
        ApplySecurityConfigurationToRepositoryJob.perform_now(**args)
      end
    end

    test "retries on turboghas errors" do
      repository_security_configuration = create(:repository_security_configuration,
        repository: @repo,
        state: "attaching",
        security_configuration: @custom_config,
      )

      SecurityProduct::ServiceManager.any_instance.stubs(:toggle_services_with_form_inputs)
        .raises(AdvancedSecurityLicense::TurboghasError, "boom")

      assert_retry_on_error AdvancedSecurityLicense::TurboghasError,
        ApplySecurityConfigurationToRepositoryJob,
        [{ actor_id: @user.id, repository_id: @repo.id, security_configuration_id: @custom_config.id }]
    end

    test "retries on AutoCodeqlError errors" do
      repository_security_configuration = create(:repository_security_configuration,
        repository: @repo,
        state: "attaching",
        security_configuration: @custom_config,
      )

      SecurityProduct::ServiceManager.any_instance.stubs(:toggle_services_with_form_inputs)
        .raises(CodeScanning::AutoCodeqlError, "boom")

      assert_retry_on_error CodeScanning::AutoCodeqlError,
        ApplySecurityConfigurationToRepositoryJob,
        [{ actor_id: @user.id, repository_id: @repo.id, security_configuration_id: @custom_config.id }]
    end
  end

  context "progress tracking" do
    test "it skips progress tracking on repo creation" do
      security_configuration = create(
        :security_configuration,
        target: @org,
        dependabot_alerts: :enabled,
        dependency_graph: :enabled,
        code_scanning: :not_set,
        secret_scanning: :not_set,
        secret_scanning_push_protection: :not_set,
      )
      repository_security_configuration = create(:repository_security_configuration, repository: @repo, security_configuration: security_configuration)

      SecurityProductsEnablement::JobProgressTracker.any_instance.expects(:decrement_jobs).never
      SecurityProductsEnablement::JobProgressTracker.any_instance.expects(:finish).never
      ApplySecurityConfigurationToRepositoryJob.perform_now(
        actor_id: @user.id,
        repository_id: @repo.id,
        security_configuration_id: security_configuration.id,
        reason: :repo_creation,
      )
    end

    test "it skips progress tracking on repo transfer" do
      security_configuration = create(
        :security_configuration,
        target: @org,
        dependabot_alerts: :enabled,
        dependency_graph: :enabled,
        code_scanning: :not_set,
        secret_scanning: :not_set,
        secret_scanning_push_protection: :not_set,
      )
      repository_security_configuration = create(:repository_security_configuration, repository: @repo, security_configuration: security_configuration)

      SecurityProductsEnablement::JobProgressTracker.any_instance.expects(:decrement_jobs).never
      SecurityProductsEnablement::JobProgressTracker.any_instance.expects(:finish).never
      ApplySecurityConfigurationToRepositoryJob.perform_now(
        actor_id: @user.id,
        repository_id: @repo.id,
        security_configuration_id: security_configuration.id,
        reason: :repo_transfer,
      )
    end

    test "it decrements the job progress tracker after running" do
      security_configuration = create(
        :security_configuration,
        target: @org,
        dependabot_alerts: :enabled,
        dependency_graph: :enabled,
        code_scanning: :not_set,
        secret_scanning: :not_set,
        secret_scanning_push_protection: :not_set,
      )
      repository_security_configuration = create(:repository_security_configuration, repository: @repo, security_configuration: security_configuration)

      SecurityProductsEnablement::JobProgressTracker.any_instance.expects(:decrement_jobs).once.returns(0)
      SecurityProductsEnablement::JobProgressTracker.any_instance.expects(:finish).once
      ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @repo.id, security_configuration_id: security_configuration.id)
    end

    test "it decrements the job progress tracker after running when the job fails" do
      security_configuration = create(:security_configuration, :not_set, target: @org)
      repository_security_configuration = create(:repository_security_configuration, repository: @repo, security_configuration: security_configuration)

      SecurityProductsEnablement::JobProgressTracker.any_instance.expects(:decrement_jobs).once.returns(0)
      SecurityProductsEnablement::JobProgressTracker.any_instance.expects(:finish).once
      ApplySecurityConfigurationToRepositoryJob.any_instance.expects(:perform)
        .raises(ApplySecurityConfigurationToRepositoryJob::FatalError, "boom")

      ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @repo.id, security_configuration_id: security_configuration.id)
    end

    test "it decrements the job progress tracker after a successful retry" do
      security_configuration = create(:security_configuration, :not_set, target: @org)
      repository_security_configuration = create(:repository_security_configuration, repository: @repo, security_configuration: security_configuration)

      SecurityProductsEnablement::JobProgressTracker.any_instance.expects(:decrement_jobs).once.returns(0)
      SecurityProductsEnablement::JobProgressTracker.any_instance.expects(:finish).once

      # Simulate a scenario where repository cannot be found on the first attempt
      Repositories::Public.stubs(:find_active)
        .returns(nil)
        .then
        .returns(@repo)

      perform_enqueued_jobs only: ApplySecurityConfigurationToRepositoryJob do
        ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @repo.id, security_configuration_id: security_configuration.id)
      end
    end

    test "it collects repository IDs for group backfill upon completion" do
      security_configuration = create(:security_configuration, target: @org, secret_scanning: :enabled)
      repository_security_configuration = create(:repository_security_configuration, repository: @repo, security_configuration: security_configuration)

      job =
        ApplySecurityConfigurationToRepositoryJob.new(
          actor_id: @user.id,
          repository_id: @repo.id,
          security_configuration_id: security_configuration.id,
          override_params: {
            skip_backfill_request: "1",
          },
        )
      job_progress_tracker = job.job_progress_tracker

      # This happens in OrganizationSecurityConfigurationJob
      job_progress_tracker.start
      job_progress_tracker.increment_jobs
      job_progress_tracker.append_repository_id(@repo.id)

      # Wrapping in a hard timeout to prevent an infinite loop as was
      # identified in: https://github.com/github/github/pull/339299
      begin
        Timeout.timeout(5) do
          job.perform_now
        end
      rescue => error
        if error.is_a?(Timeout::Error) || error.cause&.is_a?(Timeout::ExitException)
          flunk "Infinite loop detected when publishing group backfill requests."
        else
          raise
        end
      else
        pass
      end

      assert_hydro_messages(count: 1, schema: "token_scanning_service.v0.BackfillGroupRequest")
      assert_hydro_published_partial({
        owner_id: @repo.owner.id,
        owner_scope: :ORGANIZATION_SCOPE,
        backfill_type: :FULL,
        action: :START,
        repository_ids: [@repo.id],
        security_configuration_id: security_configuration.id,
      }, schema: "token_scanning_service.v0.BackfillGroupRequest")
    end
  end

  context "blocked settings" do
    test "does nothing on :repo_creation" do
      repository_security_configuration = create(:repository_security_configuration, repository: @repo, security_configuration: @custom_config)

      assert_equal 0, block_counter

      ApplySecurityConfigurationToRepositoryJob.perform_later(actor_id: @user.id, repository_id: @repo.id, security_configuration_id: @custom_config.id, reason: :repo_creation)

      assert_equal 0, block_counter

      perform_enqueued_jobs only: ApplySecurityConfigurationToRepositoryJob
      assert_equal 0, block_counter
    end

    test "manages block counter for a single repository" do
      repository_security_configuration = create(:repository_security_configuration, repository: @repo, security_configuration: @custom_config)

      assert_equal 0, block_counter

      ApplySecurityConfigurationToRepositoryJob.perform_later(actor_id: @user.id, repository_id: @repo.id, security_configuration_id: @custom_config.id)

      assert_equal 5, block_counter

      perform_enqueued_jobs only: ApplySecurityConfigurationToRepositoryJob
      assert_equal 0, block_counter
    end

    test "manages block counter for multiple repositories" do
      assert_equal 0, block_counter

      1.upto(5) do |i|
        repo = create(:private_repository, owner: @org)
        repository_security_configuration = create(:repository_security_configuration, repository: repo, security_configuration: @custom_config)
        ApplySecurityConfigurationToRepositoryJob.perform_later(actor_id: @user.id, repository_id: repo.id, security_configuration_id: @custom_config.id)

        assert_equal i * 5, block_counter
      end

      perform_enqueued_jobs only: ApplySecurityConfigurationToRepositoryJob
      assert_equal 0, block_counter
    end

    test "maintains counter on retry" do
      assert_equal 0, block_counter

      repo = create(:private_repository, owner: @org)
      repository_security_configuration = create(:repository_security_configuration, repository: repo, security_configuration: @custom_config)
      ApplySecurityConfigurationToRepositoryJob.perform_later(actor_id: @user.id, repository_id: repo.id, security_configuration_id: @custom_config.id)

      assert_equal 5, block_counter

      ApplySecurityConfigurationToRepositoryJob.any_instance.expects(:perform)
        .raises(Redis::CommandError, "boom")

      assert_enqueued_jobs(1, only: ApplySecurityConfigurationToRepositoryJob) do
        perform_enqueued_jobs only: ApplySecurityConfigurationToRepositoryJob
      end
      assert_equal 5, block_counter
    end

    test "decrements counter on terminal error" do
      assert_equal 0, block_counter

      repo = create(:private_repository, owner: @org)
      repository_security_configuration = create(:repository_security_configuration, repository: repo, security_configuration: @custom_config)
      ApplySecurityConfigurationToRepositoryJob.perform_later(actor_id: @user.id, repository_id: repo.id, security_configuration_id: @custom_config.id)

      assert_equal 5, block_counter

      ApplySecurityConfigurationToRepositoryJob.any_instance.expects(:perform)
        .raises(RuntimeError, "boom")

      assert_raises do
        perform_enqueued_jobs only: ApplySecurityConfigurationToRepositoryJob
      end
      assert_equal 0, block_counter
    end
  end

  context "license consumption" do
    test "enables GHAS features on public repos", skip_enterprise: true do
      setup_entity_as_non_ghas(@business)

      repo = create(:public_repository, owner: @org)
      repo_security_configuration = create(:repository_security_configuration, repository: repo, security_configuration: @custom_config)

      expects_auto_codeql_enabled
      ApplySecurityConfigurationToRepositoryJob.perform_now(
        actor_id: @user.id,
        repository_id: repo.id,
        security_configuration_id: @custom_config.id,
        prevent_additional_sku_usage: [GitHub::Turboghas::SKU::Bundled]
      )

      # Expect the RepositorySecurityConfiguration to be persisted:
      assert RepositorySecurityConfiguration.exists?(id: repo_security_configuration.id)
      assert_equal "attached", repo_security_configuration.reload.state

      # Expect free features to be enabled:
      assert_predicate repo, :dependency_graph_enabled?
      assert_predicate repo, :vulnerability_alerts_enabled?

      # Expect GHAS features to be enabled:
      assert_predicate repo, :code_scanning_enabled?
    end

    test "enables GHAS features on private repos with GHAS already enabled" do
      # Enable GHAS on this repo before applying:
      assert @repo.enable_advanced_security(actor: @user)

      repo_security_config = create(:repository_security_configuration, repository: @repo, security_configuration: @custom_config)

      expects_auto_codeql_enabled
      ApplySecurityConfigurationToRepositoryJob.perform_now(
        actor_id: @user.id,
        repository_id: @repo.id,
        security_configuration_id: @custom_config.id,
        prevent_additional_sku_usage: [GitHub::Turboghas::SKU::Bundled],
      )

      # Expect the RepositorySecurityConfiguration to be around:
      assert RepositorySecurityConfiguration.exists?(id: repo_security_config.id)
      assert_equal "attached", repo_security_config.reload.state

      @repo.reload
      # Expect free features to be enabled:
      assert_predicate @repo, :dependency_graph_enabled?
      assert_predicate @repo, :vulnerability_alerts_enabled?

      # Expect GHAS features to be enabled:
      assert_predicate @repo, :advanced_security_enabled?
      assert_predicate @repo, :code_scanning_enabled?
    end

    test "enables GHAS features on private repos with GHAS disabled if additional licenses aren't required" do
      # Ensure GHAS is currently disabled on this repository:
      refute_predicate @repo, :advanced_security_enabled?

      # Stub a response indicating no additional licenses are required:
      AdvancedSecurityLicense.any_instance.expects(:seat_usage_increase_if_enabled_for_repo).returns(0).at_least_once

      repo_security_config = create(:repository_security_configuration, repository: @repo, security_configuration: @custom_config)

      expects_auto_codeql_enabled
      ApplySecurityConfigurationToRepositoryJob.perform_now(
        actor_id: @user.id,
        repository_id: @repo.id,
        security_configuration_id: @custom_config.id,
        prevent_additional_sku_usage: [GitHub::Turboghas::SKU::Bundled],
      )

      # Expect the RepositorySecurityConfiguration to be persisted:
      assert RepositorySecurityConfiguration.exists?(id: repo_security_config.id)
      assert_equal "attached", repo_security_config.reload.state

      @repo.reload
      # Expect free features to be enabled:
      assert_predicate @repo, :dependency_graph_enabled?
      assert_predicate @repo, :vulnerability_alerts_enabled?

      # Expect GHAS features to be enabled:
      assert_predicate @repo, :advanced_security_enabled?
      assert_predicate @repo, :code_scanning_enabled?
    end

    test "enables GHAS features on private repos with GHAS disabled if additional licenses are allowed" do
      # Ensure GHAS is currently disabled on this repository:
      refute_predicate @repo, :advanced_security_enabled?

      # Stub a response indicating additional licenses are required:
      AdvancedSecurityLicense.stubs(:seat_usage_increase_if_advanced_security_enabled_for_repo)
        .with(@repo)
        .returns(123)

      repo_security_config = create(:repository_security_configuration, repository: @repo, security_configuration: @custom_config)

      expects_auto_codeql_enabled
      ApplySecurityConfigurationToRepositoryJob.perform_now(
        actor_id: @user.id,
        repository_id: @repo.id,
        security_configuration_id: @custom_config.id,
      )

      # Expect the RepositorySecurityConfiguration to be persisted:
      assert RepositorySecurityConfiguration.exists?(id: repo_security_config.id)
      assert_equal "attached", repo_security_config.reload.state

      @repo.reload
      # Expect free features to be enabled:
      assert_predicate @repo, :dependency_graph_enabled?
      assert_predicate @repo, :vulnerability_alerts_enabled?

      # Expect GHAS features to be enabled:
      assert_predicate @repo, :advanced_security_enabled?
      assert_predicate @repo, :code_scanning_enabled?
    end

    test "doesn't enable GHAS features on private repos if the org doesn't have GHAS" do
      security_configuration = create(
        :security_configuration,
        target: @org,
        dependabot_security_updates: :enabled,
        dependabot_alerts: :enabled,
        dependency_graph: :enabled,
        code_scanning: :enabled,
        secret_scanning: :enabled,
        secret_scanning_push_protection: :enabled,
        enable_ghas: true,
      )

      setup_entity_as_non_ghas(@business)

      # Ensure GHAS is currently disabled on this repository:
      refute_predicate @repo, :advanced_security_enabled?

      # Ensure no additional seats are needed to enable GHAS (because GHAS hasn't been purchased)
      assert_equal 0, @repo.owner.advanced_security_license.seat_usage_increase_if_enabled_for_repo(@repo)

      repo_security_config = create(:repository_security_configuration, repository: @repo, security_configuration: security_configuration)

      # Ensure no exceptions are logged, i.e. ("Advanced security has not been purchased.")
      refute_logged("apply_security_configuration_to_repository_job.service_manager_error" => /./) do
        ApplySecurityConfigurationToRepositoryJob.perform_now(
          actor_id: @user.id,
          repository_id: @repo.id,
          security_configuration_id: security_configuration.id,
        )
      end

      repo_security_config.reload
      # Expect the RepositorySecurityConfiguration to be updated:

      assert_equal "Advanced security has not been purchased.", repo_security_config.failure_reason

      @repo.reload
      # Expect free features to be enabled:
      assert_predicate @repo, :dependency_graph_enabled?
      assert_predicate @repo, :vulnerability_alerts_enabled?
      assert_predicate @repo, :vulnerability_updates_enabled?

      # Expect GHAS features to be disabled:
      refute_predicate @repo, :code_scanning_enabled?
      refute SecretScanning::Features::Repo::TokenScanning.new(@repo).enabled?
      refute_predicate @repo, :advanced_security_enabled?
    end

    test "doesn't enable GHAS features for gh recommended config and updates the associated repo security config  as failed", skip_enterprise: true do
      setup_entity_as_non_ghas(@business)

      security_configuration = T.must(SecurityConfiguration.github_recommended_configuration)

      repository_security_configuration = create(:repository_security_configuration, repository: @repo, security_configuration: security_configuration)

      ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @repo.id, security_configuration_id: security_configuration.id)

      repository_security_configuration.reload

      assert repository_security_configuration.failed?
      assert_equal "Advanced security has not been purchased.", repository_security_configuration.failure_reason
      assert_predicate @repo, :dependency_graph_enabled?
      assert_predicate @repo, :vulnerability_alerts_enabled?
      refute_predicate @repo, :vulnerability_updates_enabled?
      refute_predicate @repo, :private_vulnerability_reporting_enabled? # PVR only exists on public repos
      refute_predicate @repo, :code_scanning_enabled?
      refute SecretScanning::Features::Repo::TokenScanning.new(@repo).enabled?
    end

    test "doesn't enable GHAS features on private repos with GHAS disabled if additional licenses are required" do
      # Ensure GHAS is currently disabled on this repository:
      refute_predicate @repo, :advanced_security_enabled?

      # Stub a response indicating additional licenses are required:
      AdvancedSecurityLicense.any_instance.expects(:seat_usage_increase_if_enabled_for_repo)
        .with(@repo)
        .returns(123)

      repo_security_config = create(:repository_security_configuration, repository: @repo, security_configuration: @custom_config)

      ApplySecurityConfigurationToRepositoryJob.perform_now(
        actor_id: @user.id,
        repository_id: @repo.id,
        security_configuration_id: @custom_config.id,
        prevent_additional_sku_usage: [GitHub::Turboghas::SKU::Bundled],
      )

      repo_security_config.reload
      # Expect the RepositorySecurityConfiguration to be updated:
      assert repo_security_config.failed?
      assert_equal "Enabling advanced security would exceed seat allowance.", repo_security_config.failure_reason

      @repo.reload
      # Expect free features to be enabled:
      assert_predicate @repo, :dependency_graph_enabled?
      assert_predicate @repo, :vulnerability_alerts_enabled?

      # Expect GHAS features to be disabled:
      refute_predicate @repo, :code_scanning_enabled?
      refute_predicate @repo, :advanced_security_enabled?
    end

    test "doesn't enable GHAS on any private repos when the org already exceeded the license limit" do
      # Ensure GHAS is currently disabled on this repository:
      refute_predicate @repo, :advanced_security_enabled?

      # Stub a response indicating additional no licenses are required:
      AdvancedSecurityLicense.stubs(:seat_usage_increase_if_advanced_security_enabled_for_repo).returns(0)
      AdvancedSecurityLicense.any_instance.stubs(:allowance_exceeded?).returns(true)

      repo_security_config = create(:repository_security_configuration, repository: @repo, security_configuration: @custom_config)

      ApplySecurityConfigurationToRepositoryJob.perform_now(
        actor_id: @user.id,
        repository_id: @repo.id,
        security_configuration_id: @custom_config.id,
        prevent_additional_sku_usage: [GitHub::Turboghas::SKU::Bundled],
      )

      repo_security_config.reload
      # Expect the RepositorySecurityConfiguration to be updated:
      assert repo_security_config.failed?
      assert_equal "Enabling advanced security would exceed seat allowance.", repo_security_config.failure_reason

      @repo.reload
      # Expect free features to be enabled:
      assert_predicate @repo, :dependency_graph_enabled?
      assert_predicate @repo, :vulnerability_alerts_enabled?

      # Expect GHAS features to be disabled:
      refute_predicate @repo, :code_scanning_enabled?
      refute_predicate @repo, :advanced_security_enabled?
    end

    test "doesn't enabling GHAS when enabling GHAS is restricted by policy" do
      # Ensure GHAS is currently disabled on this repository:
      refute_predicate @repo, :advanced_security_enabled?

      @business.disallow_members_to_enable_advanced_security(actor: @user)

      repo_security_config = create(:repository_security_configuration, repository: @repo, security_configuration: @custom_config)

      # Ensure no exceptions are logged, i.e. ("Enabling advanced security is restricted by a policy.")
      refute_logged("apply_security_configuration_to_repository_job.service_manager_error" => /./) do
        ApplySecurityConfigurationToRepositoryJob.perform_now(
          actor_id: @user.id,
          repository_id: @repo.id,
          security_configuration_id: @custom_config.id,
        )
      end

      repo_security_config.reload
      # Expect the RepositorySecurityConfiguration to be updated:
      assert repo_security_config.failed?
      assert_equal "Enabling advanced security is restricted by a policy.", repo_security_config.failure_reason

      @repo.reload
      # Expect free features to be enabled:
      assert_predicate @repo, :dependency_graph_enabled?
      assert_predicate @repo, :vulnerability_alerts_enabled?

      # Expect GHAS features to be disabled:
      refute_predicate @repo, :code_scanning_enabled?
      refute_predicate @repo, :advanced_security_enabled?
    end

    test "applies non-ghas config to a non-ghas org" do
      setup_entity_as_non_ghas(@business)

      # Ensure GHAS is currently disabled on this repository:
      refute_predicate @repo, :advanced_security_enabled?

      # Ensure no additional seats are needed to enable GHAS (because GHAS hasn't been purchased)
      assert_equal 0, AdvancedSecurityLicense.seat_usage_increase_if_advanced_security_enabled_for_repo(@repo)

      # non-ghas config
      configuration = create(
        :security_configuration,
        target: @org,
        enable_ghas: false,
        dependabot_alerts: :enabled,
        dependency_graph: :enabled,
        code_scanning: :disabled,
        secret_scanning: :disabled,
        secret_scanning_push_protection: :disabled,
      )

      repo_security_config = create(:repository_security_configuration, repository: @repo, security_configuration: configuration)

      # Ensure no exceptions are logged, i.e. ("Advanced security has not been purchased.")
      refute_logged("apply_security_configuration_to_repository_job.service_manager_error" => /./) do
        ApplySecurityConfigurationToRepositoryJob.perform_now(
          actor_id: @user.id,
          repository_id: @repo.id,
          security_configuration_id: configuration.id,
        )
      end

      repo_security_config.reload

      # Expect the RepositorySecurityConfiguration to be attached:
      assert repo_security_config.attached?

      @repo.reload
      # Expect free features to be enabled:
      assert_predicate @repo, :dependency_graph_enabled?
      assert_predicate @repo, :vulnerability_alerts_enabled?

      # Expect GHAS features to be disabled:
      refute_predicate @repo, :code_scanning_enabled?
      refute_predicate @repo, :advanced_security_enabled?
    end

    context "on GHES", enterprise_only: true do
      test "doesn't skip enabling GHAS features on public repos if additional licenses aren't required" do
        # Ensure GHAS is currently disabled on this repository:
        refute_predicate @public_repo, :advanced_security_enabled?

        # Stub a response indicating no additional licenses are required:
        AdvancedSecurityLicense.any_instance.expects(:seat_usage_increase_if_enabled_for_repo)
          .with(@public_repo)
          .returns(0)

        repo_security_config = create(:repository_security_configuration, repository: @public_repo, security_configuration: @custom_config)

        ApplySecurityConfigurationToRepositoryJob.perform_now(
          actor_id: @user.id,
          repository_id: @public_repo.id,
          security_configuration_id: @custom_config.id,
          prevent_additional_sku_usage: [GitHub::Turboghas::SKU::Bundled],
        )

        # Expect the RepositorySecurityConfiguration to be persisted:
        assert RepositorySecurityConfiguration.exists?(id: repo_security_config.id)
        assert_equal "attached", repo_security_config.reload.state

        @public_repo.reload

        assert_predicate @public_repo, :advanced_security_enabled?
        assert_predicate @public_repo, :code_scanning_enabled?
      end

      test "skips enabling GHAS features on public repos if the org doesn't have GHAS" do
        setup_entity_as_non_ghas(@business)

        # Ensure GHAS is currently disabled on this repository:
        refute_predicate @public_repo, :advanced_security_enabled?

        # Ensure no additional seats are needed to enable GHAS (because GHAS hasn't been purchased)
        assert_equal 0, AdvancedSecurityLicense.seat_usage_increase_if_advanced_security_enabled_for_repo(@public_repo)

        repo_security_config = create(:repository_security_configuration, repository: @public_repo, security_configuration: @custom_config)

        ApplySecurityConfigurationToRepositoryJob.perform_now(
          actor_id: @user.id,
          repository_id: @public_repo.id,
          security_configuration_id: @custom_config.id,
        )

        repo_security_config.reload

        assert repo_security_config.failed?
        assert_equal "Advanced security has not been purchased.", repo_security_config.failure_reason

        @public_repo.reload

        # Expect free features to be enabled:
        assert_predicate @public_repo, :dependency_graph_enabled?
        assert_predicate @public_repo, :vulnerability_alerts_enabled?

        # Expect GHAS features to be disabled:
        refute_predicate @public_repo, :code_scanning_enabled?
        refute_predicate @public_repo, :advanced_security_enabled?
      end
    end
  end

  context "authorization" do
    test "fails fast if the repo is owned by a different owner than the configuration target" do
      # Set config target to a dummy ID, it doesn't matter what it is as long as it doesn't match the repo owner ID:
      @custom_config.update_attribute(:target_id, 0)

      create(:repository_security_configuration, repository: @repo, security_configuration: @custom_config)
      assert_logged(Body: "Security configuration target does not match repository's owner or enterprise") do
        ApplySecurityConfigurationToRepositoryJob.perform_now(
          actor_id: @user.id,
          repository_id: @repo.id,
          security_configuration_id: @custom_config.id
        )
      end
    end
  end

  context "user security configuration", skip_enterprise: true, skip_in_multitenant_mode: true, skip_with_all_emus: true do
    test "applies a security configuration on user owned repository" do
      repo = create(:private_repository, owner: @user)

      security_configuration = create(
        :security_configuration,
        target: @user,
        dependabot_alerts: :enabled,
        dependency_graph: :enabled,
        code_scanning: :not_set,
        secret_scanning: :not_set,
        secret_scanning_push_protection: :not_set,
      )
      repository_security_configuration = create(:repository_security_configuration, repository: repo, security_configuration: security_configuration)

      ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: repo.id, security_configuration_id: security_configuration.id)

      repository_security_configuration.reload
      repo.reload

      assert_equal "attached", repository_security_configuration.state

      # Expect free features to be enabled:
      assert_predicate repo, :dependency_graph_enabled?
      assert_predicate repo, :vulnerability_alerts_enabled?

      # Expect GHAS features to be disabled:
      refute_predicate repo, :code_scanning_enabled?
      refute_predicate repo, :advanced_security_enabled?
    end

    test "applies the github recommended configuration on a user owned repository" do
      repo = create(:private_repository, owner: @user)
      security_configuration = T.must(SecurityConfiguration.github_recommended_configuration)

      repository_security_configuration = create(:repository_security_configuration, repository: repo, security_configuration: security_configuration)

      ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: repo.id, security_configuration_id: security_configuration.id)

      repository_security_configuration.reload
      repo.reload

      assert_equal "attached", repository_security_configuration.state
      # Expect free features to be enabled:
      assert_predicate repo, :dependency_graph_enabled?
      assert_predicate repo, :vulnerability_alerts_enabled?

      # Expect GHAS features to be disabled:
      refute_predicate repo, :code_scanning_enabled?
      refute_predicate repo, :advanced_security_enabled?
    end
  end

  context "#skip_reason" do
    test "skips job when repository is not found" do
      @repo.destroy
      assert_logged(Body: "Repository not found.") do
        ApplySecurityConfigurationToRepositoryJob.perform_now(
          actor_id: @user.id,
          repository_id: @repo.id,
          security_configuration_id: @custom_config.id
        )
      end

      assert_dogstats_increment("apply_security_configuration_to_repository_job.skip", tags: ["reason:repository_not_found"])
    end

    test "skips job when repository owner is not found" do
      create(:repository_security_configuration, repository: @repo, security_configuration: @custom_config)
      @repo.owner.delete
      assert_logged(Body: "Repository Owner not found.") do
        ApplySecurityConfigurationToRepositoryJob.perform_now(
          actor_id: @user.id,
          repository_id: @repo.id,
          security_configuration_id: @custom_config.id
        )
      end

      assert_dogstats_increment("apply_security_configuration_to_repository_job.skip", tags: ["reason:owner_not_found"])
    end

    test "skips job when actor is not found" do
      assert_logged(Body: "Actor not found.") do
        ApplySecurityConfigurationToRepositoryJob.perform_now(
          actor_id: User.maximum(:id) + 1,
          repository_id: @repo.id,
          security_configuration_id: @custom_config.id
        )
      end

      assert_dogstats_increment("apply_security_configuration_to_repository_job.skip", tags: ["reason:actor_not_found"])
    end

    test "skips job when security configuration is not found" do
      assert_logged(Body: "Security configuration not found.") do
        ApplySecurityConfigurationToRepositoryJob.perform_now(
          actor_id: @user.id,
          repository_id: @repo.id,
          security_configuration_id: SecurityConfiguration.maximum(:id) + 1
        )
      end

      assert_dogstats_increment("apply_security_configuration_to_repository_job.skip", tags: ["reason:security_configuration_not_found"])
    end

    test "skips job when repository security configuration is not found" do
      assert_logged(Body: "Repository security configuration not found.") do
        ApplySecurityConfigurationToRepositoryJob.perform_now(
          actor_id: @user.id,
          repository_id: @repo.id,
          security_configuration_id: @custom_config.id
        )
      end

      assert_dogstats_increment("apply_security_configuration_to_repository_job.skip", tags: ["reason:repository_security_configuration_not_found"])
    end

    test "does not skip job when enqueued for a new repo and user cannot manage security settings" do
      create(:repository_security_configuration, repository: @repo, security_configuration: @custom_config)
      refute_logged(Body: "Actor not authorized to manage security settings.") do
        ApplySecurityConfigurationToRepositoryJob.perform_now(
          actor_id: create(:user).id,
          repository_id: @repo.id,
          security_configuration_id: @custom_config.id,
          reason: :repo_creation
        )
      end

      refute_dogstats_increment("apply_security_configuration_to_repository_job.skip", tags: ["reason:actor_not_authorized"])
    end

    test "skips job when repository owner does not match security configuration owner" do
      @custom_config.update!(target: @another_org)
      create(:repository_security_configuration, repository: @repo, security_configuration: @custom_config)

      assert_logged(Body: "Security configuration target does not match repository's owner or enterprise") do
        ApplySecurityConfigurationToRepositoryJob.perform_now(
          actor_id: @user.id,
          repository_id: @repo.id,
          security_configuration_id: @custom_config.id,
        )
      end

      assert_dogstats_increment("apply_security_configuration_to_repository_job.skip", tags: ["reason:security_configuration_owner_mismatch"])
    end

    test "it will convert a repository using the feature to using it with labeled runners" do
      security_configuration = create(
        :security_configuration,
        target: @org,
        dependency_graph: :enabled,
        dependency_graph_autosubmit_action: :enabled,
        dependency_graph_autosubmit_action_options: { "labeled_runners" => true },
      )

      repository_security_configuration = create(:repository_security_configuration, repository: @repo, security_configuration: security_configuration)

      # Pre-enable the feature without labeled runners.
      depgraph = SecurityProduct::DependencyGraph.new(@repo)
      result, _ = depgraph.enable(actor: @user)
      autosubmit = SecurityProduct::DependencyGraphAutosubmitAction.new(@repo)
      result, _ = autosubmit.enable(actor: @user)
      assert result

      ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @repo.id, security_configuration_id: security_configuration.id)
      assert_equal "attached", repository_security_configuration.reload.state

      assert_predicate autosubmit, :enabled?
      assert_predicate autosubmit, :labeled_runners_enabled?
    end
  end

  test "stores failure reason when service manager fails to enable a service" do
    CodeScanning::Status.unstub(:validate_prerequisites)
    @repo.disable_actions(actor: @user)

    security_configuration = create(
      :security_configuration,
      target: @org,
      dependabot_security_updates: :not_set,
      dependabot_alerts: :not_set,
      dependency_graph: :not_set,
      code_scanning: :enabled,
      secret_scanning: :enabled,
      secret_scanning_push_protection: :not_set,
      enable_ghas: true,
    )

    repository_security_configuration = create(:repository_security_configuration, repository: @repo, security_configuration: security_configuration)

    ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @repo.id, security_configuration_id: security_configuration.id)

    repository_security_configuration.reload
    assert_equal "failed", repository_security_configuration.state
    assert_equal "Code scanning default setup can only be enabled if Actions is enabled. GitHub Actions is disabled on this repository, please enable it.",
      repository_security_configuration.failure_reason
  end

  test "sends logs and metrics for unpreventable enablement failures" do
    CodeScanning::Status.unstub(:validate_prerequisites)
    @repo.disable_actions(actor: @user)

    security_configuration = create(
      :security_configuration,
      target: @org,
      dependabot_security_updates: :not_set,
      dependabot_alerts: :not_set,
      dependency_graph: :not_set,
      code_scanning: :enabled,
      secret_scanning: :enabled,
      secret_scanning_push_protection: :not_set,
      enable_ghas: true,
    )

    repository_security_configuration = create(:repository_security_configuration, repository: @repo, security_configuration: security_configuration)

    assert_logged("apply_security_configuration_to_repository_job.service_manager_error": "Code scanning default setup can only be enabled if Actions is enabled. GitHub Actions is disabled on this repository, please enable it.", "apply_security_configuration_to_repository_job.service_manager_error_preventable": "false") do
      ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @repo.id, security_configuration_id: security_configuration.id)
    end

    repository_security_configuration.reload
    assert_equal "failed", repository_security_configuration.state
    assert_equal "Code scanning default setup can only be enabled if Actions is enabled. GitHub Actions is disabled on this repository, please enable it.",
      repository_security_configuration.failure_reason

    assert_dogstats_increment("apply_security_configuration_to_repository_job.error", tags: ["preventable:false", "error:Code scanning default setup can only be enabled if Actions is enabled. GitHub Actions is disabled on this repository, please enable it."])
  end

  test "sends logs and metrics for preventable enablement failures" do
    SecurityProduct::Permissions::RepoAuthz.any_instance.stubs(:manage_repo_advanced_security_enablement_blocked_by_policy?).returns(true)

    # Ensure GHAS is currently disabled on this repository:
    refute_predicate @repo, :advanced_security_enabled?

    repository_security_configuration = create(:repository_security_configuration, repository: @repo, security_configuration: @custom_config)

    assert_logged(
      "apply_security_configuration_to_repository_job.service_manager_error": "An enterprise policy prevented modifying advanced security enablement. Contact your enterprise owner for details.",
      "apply_security_configuration_to_repository_job.service_manager_error_preventable": "true"
    ) do
      ApplySecurityConfigurationToRepositoryJob.perform_now(
        actor_id: @user.id,
        repository_id: @repo.id,
        security_configuration_id: @custom_config.id
      )
    end

    assert_dogstats_increment("apply_security_configuration_to_repository_job.error", tags: ["preventable:true", "error:An enterprise policy prevented modifying advanced security enablement. Contact your enterprise owner for details."])
  end

  test "can be enqueued with prevent_addtional_sku_usage" do
    repository_security_configuration = create(:repository_security_configuration, repository: @repo, security_configuration: @custom_config)

    ApplySecurityConfigurationToRepositoryJob.perform_later(
      actor_id: @user.id,
      repository_id: @repo.id,
      security_configuration_id: @custom_config.id,
      prevent_additional_sku_usage: [GitHub::Turboghas::SKU::Bundled]
    )

    assert_enqueued_jobs(1, only: ApplySecurityConfigurationToRepositoryJob)
  end

  def block_counter(security_configuration = @custom_config)
    ApplySecurityConfigurationToRepositoryJob.update_types(security_configuration).reduce(0) do |count, update_type|
      key = "security_products:enablement_count:#{@org.business&.id || 0}:#{@org.id}:#{update_type}"
      count += (SecurityProductsEnablement::KV.store.get(key).value { nil } || 0).to_i
    end
  end
end
