# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityProductsEnablement
  class HydroRepositoryTransferredJobTest < GitHub::TestCase
    include HydroMessageJobTestHelpers
    include HydroTestHelpers
    include GitHub::LoggerHelper
    include SecurityProductsEnablement::EnterpriseTestHelpers

    setup do
      @business_owner = create(:user)
      @actor = create(:user)
      @business = create(:global_business) || create(:business, owners: [@business_owner])
      @previous_owner = create(:business_plus_organization, business: @business, admin: @actor)
      @org = create(:business_plus_organization, business: @business, admin: @actor)
      @repo = create(:repository, owner: @org)
      @repository_security_configuration = create(:repository_security_configuration, :attached, repository: @repo, user: @previous_owner)

      @enterprise_config = create(:security_configuration, target: @business)
      @security_configuration = create(:security_configuration, target: @org)
      @default_configuration = create(:security_configuration_default,
        security_configuration: @security_configuration,
        target: @org,
        default_for_new_private_repos: false,
        default_for_new_public_repos: true,
      )
    end

    def perform_repo_transfer_job(repo)
      with_hydro_publisher(GitHub.sync_hydro_publisher) do
        perform_hydro_message_job({
          repository_id: repo.id,
          actor_id: @actor.id,
          previous_owner: Hydro::EntitySerializer.user(@previous_owner),
          new_owner: Hydro::EntitySerializer.user(repo.owner),
          previous_name: @previous_owner.login,
          new_name: repo.owner.login,
          new_visibility: Hydro::EntitySerializer.enum_from_string(repo.visibility)
        }, schema: "github.repositories.v1.Transferred", queue: HydroRepositoryTransferredJob.queue_name)
      end
    end

    test "deletes the corresponding repository security configuration" do
      perform_repo_transfer_job(@repo)
      assert_raises(ActiveRecord::RecordNotFound) { @repository_security_configuration.reload }
    end

    test "enqueues a ApplySecurityConfigurationToRepositoryJob" do
      perform_repo_transfer_job(@repo)

      expected_args = {
        actor_id: @actor.id,
        repository_id: @repo.id,
        security_configuration_id: @default_configuration.security_configuration_id,
        override_params: {},
        reason: :repo_transfer,
      }
      assert_enqueued_with job: ApplySecurityConfigurationToRepositoryJob, args: [expected_args]
    end

    test "it does not apply existing enterprise-level config if the new org does not belongs to same business as the previous org" do
      @repository_security_configuration.destroy

      @org = create(:organization, admin: @actor)
      @repo = create(:repository, owner: @org)
      repository_security_configuration = create(:repository_security_configuration, :attached, security_configuration: @enterprise_config, repository: @repo, user: @previous_owner)

      assert_no_enqueued_jobs(only: ApplySecurityConfigurationToRepositoryJob) do
        perform_repo_transfer_job(@repo)
      end

      assert_nil @repo.reload.repository_security_configuration
    end

    test "re-applies the existing enterprise-level config if the new org belongs to same business as the previous org" do
      @repository_security_configuration.destroy
      repository_security_configuration = create(:repository_security_configuration, :attached, security_configuration: @enterprise_config, repository: @repo, user: @previous_owner)

      perform_repo_transfer_job(@repo)

      expected_args = {
        actor_id: @actor.id,
        repository_id: @repo.id,
        security_configuration_id: @enterprise_config.id,
        override_params: {},
        reason: :repo_transfer,
      }
      assert_enqueued_with job: ApplySecurityConfigurationToRepositoryJob, args: [expected_args]

      repository_security_configuration.reload
      assert_equal @repo.owner, repository_security_configuration.user
      assert_equal "attached", repository_security_configuration.state

    end

    test "applies an enterprise-level default config if an org-level default does not exist" do
      default_configuration = create(:security_configuration_default,
        :default_for_new_public_repos,
        security_configuration: @enterprise_config,
        target: @business,
      )

      # Ensure there is NOT an org-level default:
      @default_configuration.destroy
      assert_nil SecurityConfigurationDefault.find_by(target: @org)

      perform_repo_transfer_job(@repo)

      expected_args = {
        actor_id: @actor.id,
        repository_id: @repo.id,
        security_configuration_id: @enterprise_config.id,
        override_params: {},
        reason: :repo_transfer,
      }
      assert_enqueued_with job: ApplySecurityConfigurationToRepositoryJob, args: [expected_args]
    end

    context "skipping" do
      test "it skips repositories that aren't found" do
        @repo.destroy

        assert_no_enqueued_jobs(only: ApplySecurityConfigurationToRepositoryJob) do
          perform_repo_transfer_job(@repo)
        end
      end

      test "it skips repositories that are archived" do
        repo = create(:archived_repository, owner: @org)

        assert_logged(reason: :repository_archived) do
          assert_no_enqueued_jobs(only: ApplySecurityConfigurationToRepositoryJob) do
            perform_repo_transfer_job(repo)
          end
        end
      end

      test "it skips private repositories when only a public default exists" do
        repo = create(:private_repository, owner: @org)
        refute @default_configuration.default_for_new_private_repos?

        assert_logged(reason: :no_default_configuration) do
          assert_no_enqueued_jobs(only: ApplySecurityConfigurationToRepositoryJob) do
            perform_repo_transfer_job(repo)
          end
        end
      end

      test "it skips public repositories when only a private default exists" do
        assert @repo.public?
        @default_configuration.update!(default_for_new_public_repos: false, default_for_new_private_repos: true)

        assert_logged(reason: :no_default_configuration) do
          assert_no_enqueued_jobs(only: ApplySecurityConfigurationToRepositoryJob) do
            perform_repo_transfer_job(@repo)
          end
        end
      end
    end
  end
end
