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
      @queue = HydroRepositoryTransferredJob.queue_name
      @schema = "github.repositories.v1.Transferred"
      @created_by_user = create(:user)
      @prev_owner = create :organization
      @owner = create :organization
      @repo = create(:repository, owner: @owner)
      create(:repository_security_configuration, repository: @repo, organization_id: @prev_owner.id)
    end

    test "deletes the corresponding repository security configuration" do
      with_hydro_publisher(GitHub.sync_hydro_publisher) do
        perform_hydro_message_job({
          repository_id: @repo.id,
          previous_owner: Hydro::EntitySerializer.user(@prev_owner),
          new_owner: Hydro::EntitySerializer.user(@repo.owner),
          previous_name: @prev_owner.login,
          new_name: @repo.owner.login,
          new_visibility: Hydro::EntitySerializer.enum_from_string(@repo.visibility)
        }, schema: @schema, queue: @queue)
      end

      assert_nil RepositorySecurityConfiguration.find_by(repository_id: @repo.id)
    end

    test "enqueues a ApplySecurityConfigurationToRepositoryJob" do
      created_by_user = create(:user)
      repo = create(:repository, owner: @owner, created_by_user_id: @created_by_user.id)

      security_configuration = create(:security_configuration, target: @owner)
      default_configuration = create(:security_configuration_default,
        security_configuration: security_configuration,
        target: @owner,
        default_for_new_private_repos: false,
        default_for_new_public_repos: true,
      )

      with_hydro_publisher(GitHub.sync_hydro_publisher) do
        perform_hydro_message_job({
          repository_id: repo.id,
          previous_owner: Hydro::EntitySerializer.user(@prev_owner),
          new_owner: Hydro::EntitySerializer.user(repo.owner),
          previous_name: @prev_owner.login,
          new_name: repo.owner.login,
          new_visibility: Hydro::EntitySerializer.enum_from_string(repo.visibility)
        }, schema: @schema, queue: @queue)
      end

      expected_args = {
        actor_id: @created_by_user.id,
        repository_id: repo.id,
        security_configuration_id: default_configuration.security_configuration_id,
        override_params: {},
        reason: :repo_transfer,
        skip_ghas_features: false,
      }
      assert_enqueued_with job: ApplySecurityConfigurationToRepositoryJob, args: [expected_args]
    end

    test "enqueues a ApplySecurityConfigurationToRepositoryJob when repository created_by_user is nil" do
      user = create(:user)
      repo = create(:repository, owner: @owner, created_by_user_id: nil)

      security_configuration = create(:security_configuration, target: @owner)
      default_configuration = create(:security_configuration_default,
        security_configuration: security_configuration,
        target: @owner,
        default_for_new_private_repos: false,
        default_for_new_public_repos: true,
      )

      with_hydro_publisher(GitHub.sync_hydro_publisher) do
        perform_hydro_message_job({
          repository_id: repo.id,
          previous_owner: Hydro::EntitySerializer.user(@prev_owner),
          new_owner: Hydro::EntitySerializer.user(repo.owner),
          previous_name: @prev_owner.login,
          new_name: repo.owner.login,
          new_visibility: Hydro::EntitySerializer.enum_from_string(repo.visibility)
        }, schema: @schema, queue: @queue)
      end

      expected_args = {
        actor_id: @owner.admins.first.id, # The first admin of the new owner is used as the actor
        repository_id: repo.id,
        security_configuration_id: default_configuration.security_configuration_id,
        override_params: {},
        reason: :repo_transfer,
        skip_ghas_features: false,
      }
      assert_enqueued_with job: ApplySecurityConfigurationToRepositoryJob, args: [expected_args]
    end

    context "skipping" do
      test "it skips repositories that aren't found" do
        repo = create(:repository, owner: @owner, created_by_user_id: @created_by_user.id)

        assert T.must(Repository.find_by(id: repo.id)).destroy
        assert_nil Repository.find_by(id: repo.id)

        assert_no_enqueued_jobs(only: ApplySecurityConfigurationToRepositoryJob) do
          with_hydro_publisher(GitHub.sync_hydro_publisher) do
            perform_hydro_message_job({
              repository_id: repo.id,
              previous_owner: Hydro::EntitySerializer.user(@prev_owner),
              new_owner: Hydro::EntitySerializer.user(repo.owner),
              previous_name: @prev_owner.login,
              new_name: repo.owner.login,
              new_visibility: Hydro::EntitySerializer.enum_from_string(repo.visibility)
            }, schema: @schema, queue: @queue)
          end
        end
      end

      test "it skips repositories that are archived" do
        repo = create(:archived_repository, owner: @owner, created_by_user_id: @created_by_user.id)

        security_configuration = create(:security_configuration, target: @owner)
        default_configuration = create(:security_configuration_default,
          security_configuration: security_configuration,
          target: @owner,
          default_for_new_private_repos: false,
          default_for_new_public_repos: true,
        )

        assert_logged(reason: :repository_archived) do
          assert_no_enqueued_jobs(only: ApplySecurityConfigurationToRepositoryJob) do
            with_hydro_publisher(GitHub.sync_hydro_publisher) do
              perform_hydro_message_job({
                repository_id: repo.id,
                previous_owner: Hydro::EntitySerializer.user(@prev_owner),
                new_owner: Hydro::EntitySerializer.user(repo.owner),
                previous_name: @prev_owner.login,
                new_name: repo.owner.login,
                new_visibility: Hydro::EntitySerializer.enum_from_string(repo.visibility)
              }, schema: @schema, queue: @queue)
            end
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
            with_hydro_publisher(GitHub.sync_hydro_publisher) do
              perform_hydro_message_job({
                repository_id: repo.id,
                previous_owner: Hydro::EntitySerializer.user(@prev_owner),
                new_owner: Hydro::EntitySerializer.user(repo.owner),
                previous_name: @prev_owner.login,
                new_name: repo.owner.login,
                new_visibility: Hydro::EntitySerializer.enum_from_string(repo.visibility)
              }, schema: @schema, queue: @queue)
            end
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
            with_hydro_publisher(GitHub.sync_hydro_publisher) do
              perform_hydro_message_job({
                repository_id: repo.id,
                previous_owner: Hydro::EntitySerializer.user(@prev_owner),
                new_owner: Hydro::EntitySerializer.user(repo.owner),
                previous_name: @prev_owner.login,
                new_name: repo.owner.login,
                new_visibility: Hydro::EntitySerializer.enum_from_string(repo.visibility)
              }, schema: @schema, queue: @queue)
            end
          end
        end
      end
    end
  end
end
