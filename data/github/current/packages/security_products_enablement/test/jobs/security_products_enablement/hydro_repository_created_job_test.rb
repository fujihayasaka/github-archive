# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityProductsEnablement
  class HydroRepositoryCreatedJobTest < GitHub::TestCase
    include GitHub::LoggerHelper
    include HydroMessageJobTestHelpers
    include TurboghasHelpers
    include SecurityProductsEnablement::EnterpriseTestHelpers

    fixtures do
      GitHub::Enterprise.ensure_business! if GitHub.single_business_environment?
    end

    setup do
      if GitHub.enterprise?
        GitHub.stubs(:actions_enabled?).returns(true)
        CodeScanning::Status.stubs(:validate_prerequisites).returns(nil)
      end

      @user = create(:user)
      stub_turboghas_summary(additional_committers: 1)
    end

    def publish_and_perform(repo)
      perform_hydro_message_job(
        { repository_id: repo.id, actor_id: @user.id },
        schema: "github.repositories.v1.Created",
        queue: SecurityProductsEnablement::HydroRepositoryCreatedJob.queue_name
      )
    end

    context "skipping" do
      test "it skips repositories that aren't found" do
        repo = create(:repository)

        assert T.must(::Repository.find_by(id: repo.id)).destroy
        assert_nil ::Repository.find_by(id: repo.id)

        assert_logged(reason: :repository_missing) do
          assert_no_enqueued_jobs(only: ApplySecurityConfigurationToRepositoryJob) do
            publish_and_perform(repo)
          end
        end
      end

      test "it skips repositories that are archived" do
        repo = create(:archived_repository)

        assert_logged(reason: :repository_archived) do
          assert_no_enqueued_jobs(only: ApplySecurityConfigurationToRepositoryJob) do
            publish_and_perform(repo)
          end
        end
      end

      test "it skips repositories that are owned by users" do
        repo = create(:repository, owner: create(:user))
        assert repo.owner.user?

        assert_logged(reason: :repository_owner_is_user) do
          assert_no_enqueued_jobs(only: ApplySecurityConfigurationToRepositoryJob) do
            publish_and_perform(repo)
          end
        end
      end

      test "it skips private repositories when only a public default exists" do
        owner = create(:organization)
        repo = create(:private_repository, owner:)

        security_configuration = create(:security_configuration, target: owner)
        default_configuration = create(:security_configuration_default,
          security_configuration: security_configuration,
          target: owner,
          default_for_new_private_repos: false,
          default_for_new_public_repos: true,
        )

        assert_logged(reason: :no_default_configuration) do
          assert_no_enqueued_jobs(only: ApplySecurityConfigurationToRepositoryJob) do
            publish_and_perform(repo)
          end
        end
      end

      test "it skips public repositories when only a private default exists" do
        owner = create(:organization)
        repo = create(:public_repository, owner:)

        security_configuration = create(:security_configuration, target: owner)
        default_configuration = create(:security_configuration_default,
          security_configuration: security_configuration,
          target: owner,
          default_for_new_private_repos: true,
          default_for_new_public_repos: false,
        )

        assert_logged(reason: :no_default_configuration) do
          assert_no_enqueued_jobs(only: ApplySecurityConfigurationToRepositoryJob) do
            publish_and_perform(repo)
          end
        end
      end

      test "it skips when there is no applicable default configuration and no business default settings" do
        user = create(:user)
        business = create(:global_business) || create(:business, owners: [user])
        owner = create(:business_plus_organization, business: business, admin: user)
        # Create a private repo and a default config for public repos
        repo = create(:private_repository, owner:, created_by_user_id: user.id)
        security_configuration = create(:security_configuration, target: owner)
        default_configuration = create(:security_configuration_default,
          security_configuration: security_configuration,
          target: owner,
          default_for_new_private_repos: false,
          default_for_new_public_repos: true,
        )

        assert_logged(reason: :no_default_configs_nor_business_settings) do
          assert_no_enqueued_jobs(only: ApplySecurityConfigurationToRepositoryJob) do
            publish_and_perform(repo)
          end
        end
      end
    end

    test "enqueues a ApplySecurityConfigurationToRepositoryJob" do
      owner = create(:organization)
      repo = create(:repository, owner:)

      security_configuration = create(:security_configuration, target: owner)
      default_configuration = create(:security_configuration_default,
        security_configuration: security_configuration,
        target: owner,
        default_for_new_private_repos: false,
        default_for_new_public_repos: true,
      )

      publish_and_perform(repo)

      expected_args = {
        actor_id: @user.id,
        repository_id: repo.id,
        security_configuration_id: default_configuration.security_configuration_id,
        override_params: {},
        reason: :repo_creation,
        skip_ghas_features: false,
      }
      assert_enqueued_with job: ApplySecurityConfigurationToRepositoryJob, args: [expected_args]
    end

    test "attaches a newly created private repo to gh configuration", skip_enterprise: true do
      created_by_user = create(:user)
      owner = create(:organization)

      Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)
      CodeScanning::AutoCodeql.any_instance.expects(:enabled?).once.returns(false)
      CodeScanning::AutoCodeql.any_instance.expects(:on_enable).once
        .returns(SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.empty, nil))

      repo = create(:private_repository, owner:, created_by_user_id: created_by_user.id)

      security_configuration = SecurityConfiguration.github_recommended_configuration
      default_configuration = create(:security_configuration_default,
        security_configuration: security_configuration,
        target: owner,
        default_for_new_private_repos: true,
        default_for_new_public_repos: false,
      )

      perform_enqueued_jobs only: ApplySecurityConfigurationToRepositoryJob do
        publish_and_perform(repo)
      end

      repo_config = RepositorySecurityConfiguration.where(repository_id: repo.id).first
      assert_equal T.must(repo_config).state, "attached"
    end

    test "attaches a newly created public repo to gh configuration", skip_enterprise: true do
      created_by_user = create(:user)
      owner = create(:organization)

      Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)
      CodeScanning::AutoCodeql.any_instance.expects(:enabled?).once.returns(false)
      CodeScanning::AutoCodeql.any_instance.expects(:on_enable).once
        .returns(SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.empty, nil))

      repo = create(:repository, owner:, created_by_user_id: created_by_user.id)

      security_configuration = SecurityConfiguration.github_recommended_configuration
      default_configuration = create(:security_configuration_default,
        security_configuration: security_configuration,
        target: owner,
        default_for_new_private_repos: false,
        default_for_new_public_repos: true,
      )

      perform_enqueued_jobs only: ApplySecurityConfigurationToRepositoryJob do
        publish_and_perform(repo)
      end

      repo_config = RepositorySecurityConfiguration.where(repository_id: repo.id).first
      assert_equal T.must(repo_config).state, "attached"
    end

    test "applies the default settings set by the enterprise when there is no applicable default config" do
      user = create(:user)
      business = create(:global_business) || create(:business, owners: [user])
      owner = create(:business_plus_organization, business: business, admin: user)

      if GitHub.enterprise?
        GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(true)
      else
        business.mark_advanced_security_as_purchased_for_entity(actor: user)
      end

      # Set default settings at the enterprise level
      business.enable_advanced_security_on_new_repos(actor: user)
      assert business.advanced_security_enabled_on_new_repos?

      SecretScanning::Features::Business::TokenScanning.new(business).enable_secret_scanning_for_new_repos(actor: user)
      assert SecretScanning::Features::Business::TokenScanning.new(business).secret_scanning_enabled_for_new_repos?

      SecretScanning::Features::Business::PushProtection.new(business).enable_for_new_repos(actor: user)
      assert SecretScanning::Features::Business::PushProtection.new(business).enabled_for_new_repos?

      if GitHub.flipper[SecretScanning::Features::FeatureFlagHelper::FeatureFlags::VALIDITY_CHECKS_IN_SECURITY_CONFIGURATIONS].enabled?
        SecretScanning::Features::Business::ValidityChecks.new(business).enable_for_new_repos(actor: user)
      end

      # Create a private repo and a default config for public repos
      repo = create(:private_repository, owner: owner, created_by_user_id: user.id)
      security_configuration = create(:security_configuration, target: owner)
      default_configuration = create(:security_configuration_default,
        security_configuration: security_configuration,
        target: owner,
        default_for_new_private_repos: false,
        default_for_new_public_repos: true,
      )

      publish_and_perform(repo)

      repo.reload
      assert_predicate repo, :advanced_security_enabled?
      assert_predicate SecretScanning::Features::Repo::TokenScanning.new(repo), :enabled?
      assert_predicate SecretScanning::Features::Repo::PushProtection.new(repo), :enabled?
      assert_nil RepositorySecurityConfiguration.find_by(repository_id: repo.id)

      if GitHub.flipper[SecretScanning::Features::FeatureFlagHelper::FeatureFlags::VALIDITY_CHECKS_IN_SECURITY_CONFIGURATIONS].enabled?
        assert_predicate SecretScanning::Features::Repo::ValidityChecks.new(repo), :enabled?
      end
    end

    test "applies an enterprise-level default config if an org-level default does not exist" do
      # Ensure enterprise-level configs feature flag is enabled:
      GitHub.flipper[:enterprise_security_configurations].enable

      user = create(:user)
      business = create(:global_business) || create(:business, owners: [user])
      owner = create(:business_plus_organization, business: business, admin: user)
      repo = create(:private_repository, owner:, created_by_user_id: user.id)
      enterprise_config = create(:security_configuration, target: business)
      default_configuration = create(:security_configuration_default,
        :default_for_new_private_repos,
        security_configuration: enterprise_config,
        target: business,
      )

      # Ensure there is NOT an org-level default:
      assert_nil SecurityConfigurationDefault.find_by(target: owner)

      perform_hydro_message_job(
        { repository_id: repo.id, actor_id: user.id },
        schema: "github.repositories.v1.Created",
        queue: SecurityProductsEnablement::HydroRepositoryCreatedJob.queue_name
      )
      expected_args = {
        actor_id: user.id,
        repository_id: repo.id,
        security_configuration_id: enterprise_config.id,
        override_params: {},
        reason: :repo_creation,
        skip_ghas_features: false,
      }
      assert_enqueued_with job: ApplySecurityConfigurationToRepositoryJob, args: [expected_args]
    end
  end
end
