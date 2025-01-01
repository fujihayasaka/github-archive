# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"
require "test_helpers/turboghas_helpers"

class ApplyUnbundledSecurityConfigurationToRepositoryJobTest < GitHub::TestCase
  include GitHub::LoggerHelper
  include JobTestHelper
  include TurboghasHelpers
  include HydroTestHelpers
  include DogstatsTestHelpers
  include SecurityProductsEnablement::EnterpriseTestHelpers
  include SecurityProductsEnablementHelpers
  include HydroMessageJobTestHelpers

  fixtures do
    @user = create(:verified_user)
    @business = create(:global_business) || create(:business, owners: [@user])
    @org = create(:business_plus_organization, business: @business, admin: @user)
    @another_org = create(:organization, admin: @user)
    @repo = create(:private_repository, :minimal, owner: @org)
    @public_repo = create(:public_repository, :minimal, owner: @org)
    @archived_repo = create(:archived_repository, public: false, owner: @org)
    @another_repo = create(:private_repository, :minimal, owner: @another_org)
  end

  setup do
    setup_entity_as_metered_unbundled(@business)

    stub_auto_codeql
    stub_dependency_graph_autosubmit_action

    @security_configuration_both_skus = create(
      :unbundled_security_configuration,
      :disabled,
      target: @org,
      code_security_sku_enabled: true,
      secret_protection_sku_enabled: true,
      secret_scanning: :enabled,
      code_scanning: :enabled,
    )
  end

  # We need to test combinations of security products here and see effects on repository
  context "applies security configurations with a specifc security product features to repository" do
    test "enables dependabot alerts on a repository" do
      security_configuration = create(
        :unbundled_security_configuration,
        target: @org,
        dependabot_alerts: :enabled,
        dependency_graph: :enabled,
        code_scanning: :not_set,
        secret_scanning: :not_set,
        secret_scanning_push_protection: :not_set,
      )

      repository_security_configuration = create(:repository_security_configuration, repository: @repo, security_configuration: security_configuration)

      ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @repo.id, security_configuration_id: security_configuration.id)
      refute_dogstats_increment("apply_security_configuration_to_repository_job.error")

      assert_equal "attached", repository_security_configuration.reload.state
      assert_predicate @repo, :dependency_graph_enabled?
      assert_predicate @repo, :vulnerability_alerts_enabled?
    end

    test "enables dependency graph on a repository" do
      security_configuration = create(
        :unbundled_security_configuration,
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
      refute_dogstats_increment("apply_security_configuration_to_repository_job.error")

      assert_equal "attached", repository_security_configuration.reload.state
      assert_predicate @repo, :dependency_graph_enabled?
    end

    context "dependency graph autosubmission action" do
      test "it enables autosubmission correctly" do
        security_configuration = create(
          :unbundled_security_configuration,
          target: @org,
          dependency_graph: :enabled,
          dependency_graph_autosubmit_action: :enabled,
        )

        repository_security_configuration = create(:repository_security_configuration, repository: @repo, security_configuration: security_configuration)

        ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @repo.id, security_configuration_id: security_configuration.id)
        assert_equal "attached", repository_security_configuration.reload.state
        refute_dogstats_increment("apply_security_configuration_to_repository_job.error")

        autosubmit = SecurityProduct::DependencyGraphAutosubmitAction.new(@repo)

        assert_predicate autosubmit, :enabled?
        refute_predicate autosubmit, :labeled_runners_enabled?
      end

      test "it enables autosubmission with labelled-runners correctly" do
        security_configuration = create(
          :unbundled_security_configuration,
          target: @org,
          dependency_graph: :enabled,
          dependency_graph_autosubmit_action: :enabled,
          dependency_graph_autosubmit_action_options: { "labeled_runners" => true },
        )

        repository_security_configuration = create(:repository_security_configuration, repository: @repo, security_configuration: security_configuration)

        ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @repo.id, security_configuration_id: security_configuration.id)
        refute_dogstats_increment("apply_security_configuration_to_repository_job.error")

        assert_equal "attached", repository_security_configuration.reload.state
        assert_predicate @repo, :dependency_graph_enabled?

        autosubmit = SecurityProduct::DependencyGraphAutosubmitAction.new(@repo)

        assert_predicate autosubmit, :enabled?
        assert_predicate autosubmit, :labeled_runners_enabled?
      end

      test "it cannot attach the configuration if actions is disabled on the repository" do
        @repo.disable_actions(actor: @user)

        security_configuration = create(
          :unbundled_security_configuration,
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
          :unbundled_security_configuration,
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
        :unbundled_security_configuration,
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
      refute_dogstats_increment("apply_security_configuration_to_repository_job.error")

      assert_equal "attached", repository_security_configuration.reload.state
      assert_predicate @repo, :dependency_graph_enabled?
      assert_predicate @repo, :vulnerability_alerts_enabled?
      assert_predicate @repo, :vulnerability_updates_enabled?
    end

    test "enables secret scanning on a repository" do
      security_configuration = create(
        :unbundled_security_configuration,
        :disabled,
        target: @org,
        code_security_sku_enabled: false,
        secret_protection_sku_enabled: true,
        secret_scanning: :enabled,
      )

      repository_security_configuration = create(:repository_security_configuration, repository: @repo, security_configuration: security_configuration)

      ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @repo.id, security_configuration_id: security_configuration.id)
      refute_dogstats_increment("apply_security_configuration_to_repository_job.error")

      assert_equal "attached", repository_security_configuration.reload.state
      refute_predicate @repo, :advanced_security_enabled? # in SKU split world, GHAS should be disabed on the repo
      assert SecretScanning::Features::Repo::TokenScanning.new(@repo).enabled?
    end

    test "enables secret scanning non provider patterns on a repository" do
      refute_predicate SecretScanning::Features::Repo::TokenScanning.new(@repo), :enabled?

      security_configuration = create(
        :unbundled_security_configuration,
        :disabled,
        target: @org,
        code_security_sku_enabled: false,
        secret_protection_sku_enabled: true,
        secret_scanning: :enabled,
        secret_scanning_non_provider_patterns: :enabled,
        secret_scanning_push_protection: :not_set,
      )

      repository_security_configuration = create(:repository_security_configuration, repository: @repo, security_configuration: security_configuration)

      ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @repo.id, security_configuration_id: security_configuration.id)
      refute_dogstats_increment("apply_security_configuration_to_repository_job.error")
      @repo.reload

      assert_equal "attached", repository_security_configuration.reload.state
      refute_predicate @repo, :advanced_security_enabled? # in SKU split world, GHAS should be disabed on the repo
      assert SecretScanning::Features::Repo::LowerConfidencePatterns.new(@repo).enabled?
    end

    test "enables secret scanning delegated alert closures on a repository" do
      SecretScanning::Features::Org::DelegatedClosures.any_instance.stubs(:feature_available?).returns(true)
      SecretScanning::Features::Repo::DelegatedClosures.any_instance.stubs(:feature_available?).returns(true)
      refute_predicate SecretScanning::Features::Repo::TokenScanning.new(@repo), :enabled?

      security_configuration = create(
        :unbundled_security_configuration,
        :disabled,
        target: @org,
        code_security_sku_enabled: false,
        secret_protection_sku_enabled: true,
        secret_scanning: :enabled,
        secret_scanning_delegated_alert_dismissal: :enabled,
      )

      repository_security_configuration = create(:repository_security_configuration, repository: @repo, security_configuration: security_configuration)

      ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @repo.id, security_configuration_id: security_configuration.id)
      refute_dogstats_increment("apply_security_configuration_to_repository_job.error")

      @repo.reload
      assert_equal "attached", repository_security_configuration.reload.state
      refute_predicate @repo, :advanced_security_enabled? # in SKU split world, GHAS should be disabed on the repo
      assert SecretScanning::Features::Repo::DelegatedClosures.new(@repo).enabled?
    end

    test "enables secret scanning push protection on a repository" do
      refute_predicate SecretScanning::Features::Repo::TokenScanning.new(@repo), :enabled?

      security_configuration = create(
        :unbundled_security_configuration,
        :disabled,
        target: @org,
        code_security_sku_enabled: false,
        secret_protection_sku_enabled: true,
        secret_scanning: :enabled,
        secret_scanning_push_protection: :enabled,
      )

      repository_security_configuration = create(:repository_security_configuration, repository: @repo, security_configuration: security_configuration)

      ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @repo.id, security_configuration_id: security_configuration.id)
      refute_dogstats_increment("apply_security_configuration_to_repository_job.error")
      @repo.reload

      assert_equal "attached", repository_security_configuration.reload.state
      refute_predicate @repo, :advanced_security_enabled? # in SKU split world, GHAS should be disabed on the repo
      assert SecretScanning::Features::Repo::TokenScanning.new(@repo).enabled?
      assert @repo.security_feature_configured?(:SECRET_SCANNING_PUSH_PROTECTION)
    end

    test "enables secret scanning push protection and delegated bypass on a repository being imported" do
      @repo.importing_started!

      security_configuration = create(
        :unbundled_security_configuration,
        :disabled,
        target: @org,
        code_security_sku_enabled: false,
        secret_protection_sku_enabled: true,
        secret_scanning: :enabled,
        secret_scanning_push_protection: :enabled,
        secret_scanning_delegated_bypass: :enabled,
      )

      repository_security_configuration = create(:repository_security_configuration, repository: @repo, security_configuration: security_configuration)

      ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @repo.id, security_configuration_id: security_configuration.id)
      refute_dogstats_increment("apply_security_configuration_to_repository_job.error")

      @repo.importing_stopped!

      assert_equal "attached", repository_security_configuration.reload.state
      refute_predicate @repo, :advanced_security_enabled? # in SKU split world, GHAS should be disabed on the repo
      assert_equal true, SecretScanning::Features::Repo::PushProtection.new(@repo).enabled?
      assert_equal true, SecretScanning::Features::Repo::DelegatedBypass.new(@repo).enabled?
    end

    test "enables secret scanning when modifying code security is not allowed" do
      @business.set_advanced_security_enabled_type_for_entity(option: Configurable::AdvancedSecurityBillingConfig::SPLIT_VOLUME, actor: @user)
      @business.set_code_security_license_count(count: 5, actor: @user)
      @business.set_secret_scanning_license_count(count: 5, actor: @user)
      assert @business.secret_protection_purchased?
      assert @business.code_security_purchased?

      @repo.enable_code_security!(actor: @user)
      assert_predicate(@repo, :code_scanning_enabled?)

      @business.allow_selected_members_to_enable_advanced_security(actor: @user)
      @org.set_advanced_security_entity_policy(policy: Configurable::AdvancedSecurityAccessPolicy::ENTITY_ALLOWED_SECRET_PROTECTION_ONLY, actor: @user)

      repository_security_configuration = create(:repository_security_configuration, repository: @repo, security_configuration: @security_configuration_both_skus)
      ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @repo.id, security_configuration_id: @security_configuration_both_skus.id)
      refute_dogstats_increment("apply_security_configuration_to_repository_job.error")

      @repo.reload

      assert_equal "attached", repository_security_configuration.reload.state
      assert_nil repository_security_configuration.failure_reason

      assert_predicate @repo, :code_scanning_enabled?
      assert SecretScanning::Features::Repo::TokenScanning.new(@repo).enabled?
    end

    test "enables code scanning on a repository" do
      security_configuration = create(
        :unbundled_security_configuration,
        :disabled,
        target: @org,
        code_security_sku_enabled: true,
        secret_protection_sku_enabled: false,
        code_scanning: :enabled,
      )

      repository_security_configuration = create(:repository_security_configuration, repository: @repo, security_configuration: security_configuration)

      expects_auto_codeql_enabled
      ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @repo.id, security_configuration_id: security_configuration.id)
      refute_dogstats_increment("apply_security_configuration_to_repository_job.error")

      assert_equal "attached", repository_security_configuration.reload.state
      refute_predicate @repo, :advanced_security_enabled? # in SKU split world, GHAS should be disabed on the repo

      assert_predicate @repo, :code_security_enabled?
      assert @repo, :code_scanning_enabled?
    end

    context "dotcom only features", skip_enterprise: true do
      test "enables paid features on a public repo", skip_enterprise: true do
        security_configuration = create(
          :unbundled_security_configuration,
          :disabled,
          target: @org,
          code_security_sku_enabled: true,
          secret_protection_sku_enabled: true,
          secret_scanning: :enabled,
          code_scanning: :enabled,
        )

        repository_security_configuration = create(:repository_security_configuration, repository: @public_repo, security_configuration: security_configuration)

        expects_auto_codeql_enabled
        ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @public_repo.id, security_configuration_id: security_configuration.id)
        refute_dogstats_increment("apply_security_configuration_to_repository_job.error")

        assert_equal "attached", repository_security_configuration.reload.state
        refute_predicate @public_repo, :advanced_security_enabled? # in SKU split world, GHAS should be disabed on the repo
        refute_predicate @public_repo, :code_security_enabled? # Code Security is free for public repos
        assert @public_repo, :code_scanning_enabled?
        assert SecretScanning::Features::Repo::TokenScanning.new(@public_repo).enabled?
      end

      test "enables private vulnerability alerting on a repository" do
        # PVR only exists on public repos
        repo = create(:repository, owner: @org)

        security_configuration = create(
          :unbundled_security_configuration,
          target: @org,
          private_vulnerability_reporting: :enabled,
          dependabot_security_updates: :not_set,
          dependabot_alerts: :not_set,
          dependency_graph: :not_set,
          code_scanning: :not_set,
          secret_scanning: :not_set,
          secret_scanning_push_protection: :not_set,
        )

        repository_security_configuration = create(:repository_security_configuration, repository: repo, security_configuration: security_configuration)

        ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: repo.id, security_configuration_id: security_configuration.id)
        refute_dogstats_increment("apply_security_configuration_to_repository_job.error")

        assert_equal "attached", repository_security_configuration.reload.state
        assert_predicate repo, :private_vulnerability_reporting_enabled?
      end

      test "enables secret scanning validity check on a repository" do
        security_configuration = create(
          :unbundled_security_configuration,
          :not_set,
          target: @org,
          secret_scanning: :enabled,
          secret_scanning_validity_checks: :enabled,
          secret_scanning_push_protection: :not_set,
        )

        repository_security_configuration = create(:repository_security_configuration, repository: @repo, security_configuration: security_configuration)

        ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @repo.id, security_configuration_id: security_configuration.id)
        refute_dogstats_increment("apply_security_configuration_to_repository_job.error")

        assert_equal "attached", repository_security_configuration.reload.state
        refute_predicate @repo, :advanced_security_enabled?
        assert SecretScanning::Features::Repo::ValidityChecks.new(@repo).enabled?
      end
    end

    context "grouped security updates" do
      test "enables grouped security updates on a repository" do
        @org.enable_vulnerability_updates_grouping_for_new_repos(actor: @user)

        security_configuration = create(
          :unbundled_security_configuration,
          target: @org,
          dependabot_security_updates: :enabled,
          dependabot_alerts: :enabled,
          dependency_graph: :enabled,
          code_scanning: :not_set,
          secret_scanning: :not_set,
          secret_scanning_push_protection: :not_set,
        )
        repository_security_configuration = create(:repository_security_configuration, repository: @repo, security_configuration: security_configuration)

        ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @repo.id, security_configuration_id: security_configuration.id)
        refute_dogstats_increment("apply_security_configuration_to_repository_job.error")

        assert_predicate @repo, :vulnerability_updates_enabled?
        assert_predicate @repo, :vulnerability_updates_grouping_enabled?
      end

      test "does not enable grouped security updates when security updates are not enabled" do
        @org.enable_vulnerability_updates_grouping_for_new_repos(actor: @user)

        security_configuration = create(
          :unbundled_security_configuration,
          target: @org,
          dependabot_security_updates: :not_set,
          dependabot_alerts: :enabled,
          dependency_graph: :enabled,
          code_scanning: :not_set,
          secret_scanning: :not_set,
          secret_scanning_push_protection: :not_set,
        )
        repository_security_configuration = create(:repository_security_configuration, repository: @repo, security_configuration: security_configuration)

        ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @repo.id, security_configuration_id: security_configuration.id)
        refute_dogstats_increment("apply_security_configuration_to_repository_job.error")

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
        refute_dogstats_increment("apply_security_configuration_to_repository_job.error")

        # if this job run fails, it will return an exception - let's raise it so we can debug
        raise result if result.is_a?(Exception)
        assert_equal "attached", repository_security_configuration.reload.state
        refute_predicate @repo, :advanced_security_enabled? # in SKU split world, GHAS should be disabed on the repo
        assert_predicate @repo, :code_security_enabled?
        assert_predicate @repo, :dependency_graph_enabled?
        assert_predicate @repo, :vulnerability_alerts_enabled?
        refute_predicate @repo, :vulnerability_updates_enabled?
        assert_equal true, SecretScanning::Features::Repo::TokenScanning.new(@repo).enabled?, "expected Secret Scanning to be enabled"
        assert_equal true, SecretScanning::Features::Repo::PushProtection.new(@repo).enabled?, "expected Push Protection to be enabled"
        assert @public_repo, :code_scanning_enabled?
      end

      test "applies the configuration to a public repository" do
        security_configuration = T.must(SecurityConfiguration.github_recommended_configuration)
        repository_security_configuration = create(:repository_security_configuration, repository: @public_repo, security_configuration: security_configuration)

        expects_auto_codeql_enabled
        result = T.unsafe(ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @public_repo.id, security_configuration_id: security_configuration.id))
        refute_dogstats_increment("apply_security_configuration_to_repository_job.error")

        # if this job run fails, it will return an exception - let's raise it so we can debug
        raise result if result.is_a?(Exception)
        assert_equal "attached", repository_security_configuration.reload.state
        refute_predicate @public_repo, :advanced_security_enabled? # in SKU split world, GHAS should be disabed on the repo
        refute_predicate @public_repo, :code_security_enabled? # Code Security is free for public repos
        assert_predicate @public_repo, :dependency_graph_enabled?
        assert_predicate @public_repo, :vulnerability_alerts_enabled?
        refute_predicate @public_repo, :vulnerability_updates_enabled?
        assert_equal true, SecretScanning::Features::Repo::TokenScanning.new(@public_repo).enabled?, "expected Secret Scanning to be enabled"
        assert_equal true, SecretScanning::Features::Repo::PushProtection.new(@public_repo).enabled?, "expected Push Protection to be enabled"
        assert @public_repo, :code_scanning_enabled?
      end

      test "enables the Dependabot default rule" do
        security_configuration = T.must(SecurityConfiguration.github_recommended_configuration)
        repository_security_configuration = create(:repository_security_configuration, repository: @repo, security_configuration: security_configuration)

        expects_auto_codeql_enabled
        ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @repo.id, security_configuration_id: security_configuration.id)
        refute_dogstats_increment("apply_security_configuration_to_repository_job.error")

        assert_predicate @repo, :vulnerability_alerts_enabled?
        assert_equal true, RepositoryVulnerabilityAlertRules.new(repository: @repo).default_rule_enabled?, "expected the Dependabot default rule to be enabled"
      end
    end

    context "archived repository" do
      test "enables only secret scanning and some of its sub features" do
        security_configuration = create(
          :unbundled_security_configuration,
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
        )

        repository_security_configuration = create(:repository_security_configuration, repository: @archived_repo, security_configuration: security_configuration)

        ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @archived_repo.id, security_configuration_id: security_configuration.id)
        refute_dogstats_increment("apply_security_configuration_to_repository_job.error")

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
          :unbundled_security_configuration,
          target: @org,
          secret_protection_sku_enabled: false,
          code_security_sku_enabled: false,
          private_vulnerability_reporting: :disabled,
          dependabot_security_updates: :not_set,
          dependabot_alerts: :not_set,
          dependency_graph: :not_set,
          code_scanning: :disabled,
          secret_scanning: :disabled,
          secret_scanning_non_provider_patterns: :disabled,
          secret_scanning_push_protection: :disabled,
          secret_scanning_validity_checks: :disabled,
        )

        repository_security_configuration = create(:repository_security_configuration, repository: @archived_repo, security_configuration: security_configuration)

        ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @archived_repo.id, security_configuration_id: security_configuration.id)
        refute_dogstats_increment("apply_security_configuration_to_repository_job.error")
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

  context "failure reasons" do
    context "on an volume enterprise" do
      test "marks GHR as failed when secret scanning is not purchased", skip_enterprise: true do
        setup_business_as_volume_cs_only(@business)
        refute @business.secret_protection_purchased?

        ghr = T.must(SecurityConfiguration.github_recommended_configuration)
        repository_security_configuration = create(:repository_security_configuration, repository: @repo, security_configuration: ghr)
        ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @repo.id, security_configuration_id: ghr.id)
        refute_dogstats_increment("apply_security_configuration_to_repository_job.error")

        assert_equal "failed", repository_security_configuration.reload.state
        assert_equal "Secret scanning is not available for this repository.", repository_security_configuration.failure_reason

        refute SecretScanning::Features::Repo::TokenScanning.new(@repo).enabled?
        assert_predicate @repo, :code_scanning_enabled?
      end

      test "marks GHR as failed when code security is not purchased", skip_enterprise: true do
        setup_business_as_volume_sp_only(@business)
        refute @business.code_security_purchased?

        ghr = T.must(SecurityConfiguration.github_recommended_configuration)
        repository_security_configuration = create(:repository_security_configuration, repository: @repo, security_configuration: ghr)
        ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @repo.id, security_configuration_id: ghr.id)
        refute_dogstats_increment("apply_security_configuration_to_repository_job.error")

        assert_equal "failed", repository_security_configuration.reload.state
        assert_equal "Code Security has not been purchased.", repository_security_configuration.failure_reason

        refute_predicate @repo, :code_scanning_enabled?
        assert SecretScanning::Features::Repo::TokenScanning.new(@repo).enabled?
      end

      test "marks as failed when secret scanning is not purchased" do
        setup_business_as_volume_cs_only(@business)
        refute @business.secret_protection_purchased?

        repository_security_configuration = create(:repository_security_configuration, repository: @repo, security_configuration: @security_configuration_both_skus)
        ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @repo.id, security_configuration_id: @security_configuration_both_skus.id)
        refute_dogstats_increment("apply_security_configuration_to_repository_job.error")

        assert_equal "failed", repository_security_configuration.reload.state
        assert_equal "Secret scanning is not available for this repository.", repository_security_configuration.failure_reason

        refute SecretScanning::Features::Repo::TokenScanning.new(@repo).enabled?
        assert_predicate @repo, :code_scanning_enabled?
      end

      test "marks as failed when code security is not purchased" do
        setup_business_as_volume_sp_only(@business)
        refute @business.code_security_purchased?

        repository_security_configuration = create(:repository_security_configuration, repository: @repo, security_configuration: @security_configuration_both_skus)
        ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @repo.id, security_configuration_id: @security_configuration_both_skus.id)
        refute_dogstats_increment("apply_security_configuration_to_repository_job.error")

        assert_equal "failed", repository_security_configuration.reload.state
        assert_equal "Code Security has not been purchased.", repository_security_configuration.failure_reason

        refute_predicate @repo, :code_scanning_enabled?
        assert SecretScanning::Features::Repo::TokenScanning.new(@repo).enabled?
      end

      test "marks as failed when secret scanning is not allowed by policy" do
        @business.allow_selected_members_to_enable_advanced_security(actor: @user)
        @org.set_advanced_security_entity_policy(policy: Configurable::AdvancedSecurityAccessPolicy::ENTITY_ALLOWED_CODE_SECURITY_ONLY, actor: @user)

        repository_security_configuration = create(:repository_security_configuration, repository: @repo, security_configuration: @security_configuration_both_skus)
        ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @repo.id, security_configuration_id: @security_configuration_both_skus.id)
        refute_dogstats_increment("apply_security_configuration_to_repository_job.error")

        assert_equal "failed", repository_security_configuration.reload.state
        assert_equal "Modifying secret scanning and push protection has been blocked by an enterprise policy. Contact your enterprise owner for details.", repository_security_configuration.failure_reason

        refute SecretScanning::Features::Repo::TokenScanning.new(@repo).enabled?
        assert_predicate @repo, :code_scanning_enabled?
      end

      test "marks as failed when code security is not allowed by policy" do
        @business.allow_selected_members_to_enable_advanced_security(actor: @user)
        @org.set_advanced_security_entity_policy(policy: Configurable::AdvancedSecurityAccessPolicy::ENTITY_ALLOWED_SECRET_PROTECTION_ONLY, actor: @user)

        repository_security_configuration = create(:repository_security_configuration, repository: @repo, security_configuration: @security_configuration_both_skus)
        ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @repo.id, security_configuration_id: @security_configuration_both_skus.id)
        refute_dogstats_increment("apply_security_configuration_to_repository_job.error")

        assert_equal "failed", repository_security_configuration.reload.state
        assert_equal "An enterprise policy prevented modifying Code Security enablement. Contact your enterprise owner for details.", repository_security_configuration.failure_reason

        refute_predicate @repo, :code_scanning_enabled?
        assert SecretScanning::Features::Repo::TokenScanning.new(@repo).enabled?
      end

      test "marks as failed when neither is not allowed by policy" do
        @business.allow_selected_members_to_enable_advanced_security(actor: @user)
        @org.set_advanced_security_entity_policy(policy: Configurable::AdvancedSecurityAccessPolicy::ENTITY_ALLOWED_NONE, actor: @user)

        repository_security_configuration = create(:repository_security_configuration, repository: @repo, security_configuration: @security_configuration_both_skus)
        ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @repo.id, security_configuration_id: @security_configuration_both_skus.id)
        refute_dogstats_increment("apply_security_configuration_to_repository_job.error")

        assert_equal "failed", repository_security_configuration.reload.state
        assert_equal "An enterprise policy prevented modifying Code Security enablement. Contact your enterprise owner for details.", repository_security_configuration.failure_reason

        refute_predicate @repo, :code_scanning_enabled?
        refute SecretScanning::Features::Repo::TokenScanning.new(@repo).enabled?
      end

      test "marks as failed when there are insufficient secret protection licenses" do
        setup_entity_as_volume_unbundled(@business)
        assert @business.secret_protection_purchased?
        assert @business.code_security_purchased?

        secret_protection = AdvancedSecurityLicense.new(@repo.owner, sku: GitHub::Turboghas::SKU::SecretSecurity)
        secret_protection.expects(:seat_usage_increase_if_enabled_for_repo).with(@repo).returns(20)
        SecurityProductsEnablement::LicenseValidator.any_instance.stubs(secret_protection:)

        repository_security_configuration = create(:repository_security_configuration, repository: @repo, security_configuration: @security_configuration_both_skus)
        ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @repo.id, security_configuration_id: @security_configuration_both_skus.id, prevent_additional_sku_usage: [GitHub::Turboghas::SKU::SecretSecurity])
        refute_dogstats_increment("apply_security_configuration_to_repository_job.error")

        assert_equal "failed", repository_security_configuration.reload.state
        assert_equal "Enabling secret scanning would exceed available licenses.", repository_security_configuration.failure_reason

        refute SecretScanning::Features::Repo::TokenScanning.new(@repo).enabled?
        assert_predicate @repo, :code_scanning_enabled?
      end

      test "marks as failed when there are insufficient code security licenses" do
        setup_entity_as_volume_unbundled(@business)
        assert @business.secret_protection_purchased?
        assert @business.code_security_purchased?

        code_security = AdvancedSecurityLicense.new(@repo.owner, sku: GitHub::Turboghas::SKU::CodeSecurity)
        code_security.expects(:seat_usage_increase_if_enabled_for_repo).with(@repo).returns(10)
        SecurityProductsEnablement::LicenseValidator.any_instance.stubs(code_security:)

        repository_security_configuration = create(:repository_security_configuration, repository: @repo, security_configuration: @security_configuration_both_skus)
        ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @repo.id, security_configuration_id: @security_configuration_both_skus.id, prevent_additional_sku_usage: [GitHub::Turboghas::SKU::CodeSecurity])
        refute_dogstats_increment("apply_security_configuration_to_repository_job.error")

        assert_equal "failed", repository_security_configuration.reload.state
        assert_equal "Enabling Code Security would exceed seat allowance.", repository_security_configuration.failure_reason

        refute_predicate @repo, :code_scanning_enabled?
        assert SecretScanning::Features::Repo::TokenScanning.new(@repo).enabled?
      end

      test "marks as failed when secret protection is in overage" do
        setup_entity_as_volume_unbundled(@business)
        assert @business.secret_protection_purchased?
        assert @business.code_security_purchased?

        secret_protection = AdvancedSecurityLicense.new(@repo.owner, sku: GitHub::Turboghas::SKU::SecretSecurity)
        secret_protection.expects(allowance_exceeded?: true)
        SecurityProductsEnablement::LicenseValidator.any_instance.stubs(secret_protection:)

        repository_security_configuration = create(:repository_security_configuration, repository: @repo, security_configuration: @security_configuration_both_skus)
        ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @repo.id, security_configuration_id: @security_configuration_both_skus.id, prevent_additional_sku_usage: [GitHub::Turboghas::SKU::SecretSecurity])
        refute_dogstats_increment("apply_security_configuration_to_repository_job.error")

        assert_equal "failed", repository_security_configuration.reload.state
        assert_equal "Enabling secret scanning would exceed available licenses.", repository_security_configuration.failure_reason

        refute SecretScanning::Features::Repo::TokenScanning.new(@repo).enabled?
        assert_predicate @repo, :code_scanning_enabled?
      end

      test "marks as failed when code security is in overage" do
        setup_entity_as_volume_unbundled(@business)
        assert @business.secret_protection_purchased?
        assert @business.code_security_purchased?

        code_security = AdvancedSecurityLicense.new(@repo.owner, sku: GitHub::Turboghas::SKU::CodeSecurity)
        code_security.expects(allowance_exceeded?: true)
        SecurityProductsEnablement::LicenseValidator.any_instance.stubs(code_security:)

        repository_security_configuration = create(:repository_security_configuration, repository: @repo, security_configuration: @security_configuration_both_skus)
        ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @repo.id, security_configuration_id: @security_configuration_both_skus.id, prevent_additional_sku_usage: [GitHub::Turboghas::SKU::CodeSecurity])
        refute_dogstats_increment("apply_security_configuration_to_repository_job.error")

        assert_equal "failed", repository_security_configuration.reload.state
        assert_equal "Enabling Code Security would exceed seat allowance.", repository_security_configuration.failure_reason

        refute_predicate @repo, :code_scanning_enabled?
        assert SecretScanning::Features::Repo::TokenScanning.new(@repo).enabled?
      end
    end
  end

  context "GHES testing", enterprise_only: true do
    test "repo attaches when the security configuration has an uninstalled security product" do
      # uninstall DG
      stub_dependency_graph_and_dependents(false)

      repository_security_configuration = create(:repository_security_configuration, repository: @repo, security_configuration: @security_configuration_both_skus)

      ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @repo.id, security_configuration_id: @security_configuration_both_skus.id)
      refute_dogstats_increment("apply_security_configuration_to_repository_job.error")

      assert_equal "attached", repository_security_configuration.reload.state
      refute_predicate @repo, :vulnerability_alerts_enabled?
      refute_predicate @repo, :dependency_graph_enabled?
      assert_predicate @repo, :code_scanning_enabled?
    end

    test "enables billed SKUs on a public repository in GHES" do
      repository_security_configuration = create(:repository_security_configuration, repository: @public_repo, security_configuration: @security_configuration_both_skus)

      ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @public_repo.id, security_configuration_id: @security_configuration_both_skus.id)
      refute_dogstats_increment("apply_security_configuration_to_repository_job.error")

      assert_equal "attached", repository_security_configuration.reload.state
      assert_predicate @public_repo, :code_security_enabled?
      assert SecretScanning::Features::Repo::TokenScanning.new(@public_repo).enabled?
    end
  end

  test "enforces a security configuration on a repository" do
    create(:security_configuration_policy, :enforced, security_configuration: @security_configuration_both_skus, target: @org)
    repository_security_configuration = create(:repository_security_configuration, repository: @repo, security_configuration: @security_configuration_both_skus)

    assert_changes -> { repository_security_configuration.reload.state }, from: "attaching", to: "enforced" do
      ApplySecurityConfigurationToRepositoryJob.perform_now(actor_id: @user.id, repository_id: @repo.id, security_configuration_id: @security_configuration_both_skus.id)
      refute_dogstats_increment("apply_security_configuration_to_repository_job.error")
    end

    refute_predicate @repo, :advanced_security_enabled?
    assert_predicate SecretScanning::Features::Repo::TokenScanning.new(@repo), :enabled?
  end
end
