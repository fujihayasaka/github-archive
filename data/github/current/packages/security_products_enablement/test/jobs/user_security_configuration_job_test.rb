# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"
require "test_helpers/turboghas_helpers"

module SecurityProductsEnablement
  class UserSecurityConfigurationJobTest < GitHub::TestCase
    include JobTestHelper
    include TurboghasHelpers
    include SecurityProductsEnablement::EnterpriseTestHelpers

    setup do
      setup_search

      @user = create(:verified_user)
      @security_configuration = GitHub.enterprise? ? create(:security_configuration, target: @user) : SecurityConfiguration.github_recommended_configuration
      @repo1 = create(:private_repository, owner: @user)
      @repo2 = create(:private_repository, owner: @user)
      @repo3 = create(:repository, owner: @user)
      @repo4 = create(:repository, owner: @user)
      @archived_repo = create(:archived_repository, owner: @user).tap { |repo| repo.update!(public: false) }
      @deleted_repo = create(:deleted_repository, owner: @user)

      @custom_security_configuration = create(:security_configuration, :not_set, target: @user)

      make_searchable(@repo1, @repo2, @repo3, @repo4, @archived_repo)
    end

    context "applying a configuration" do
      test "applies the configuration to repositories owned by the user" do
        job =
          UserSecurityConfigurationJob.new(
            security_configuration_id: @security_configuration.id,
            user_id: @user.id,
            action: :apply,
            repository_ids: nil,
            override_existing_config: true,
          )
        job_progress_tracker = job.job_progress_tracker

        job_progress_tracker.start # Normally done when the job is enqueued.
        job.perform_now

        assert_enqueued_jobs 5, only: ApplySecurityConfigurationToRepositoryJob
        [@repo1, @repo2, @repo3, @repo4, @archived_repo].each do |repo|
          assert_enqueued_with(
            job: ApplySecurityConfigurationToRepositoryJob,
            args: [{
              actor_id: @user.id,
              repository_id: repo.id,
              security_configuration_id: @security_configuration.id,
              override_params: { skip_backfill_request: "1" },
              reason: nil,
            }]
          )
        end

        assert_predicate job_progress_tracker, :in_progress?
        assert_equal 5, job_progress_tracker.total_jobs
        assert_equal 5, job_progress_tracker.remaining_jobs
        assert_same_elements [@repo1.id, @repo2.id, @repo3.id, @repo4.id, @archived_repo.id], job_progress_tracker.repository_ids
      end

      test "applies the configuration to only repos without configuration owned by the user" do
        [@repo1, @repo3].each do |repo|
          create(:repository_security_configuration, state: :attached, repository: repo, security_configuration: @security_configuration)
        end

        assert_empty RepositorySecurityConfiguration.where(repository_id: [@repo2.id, @repo4.id, @archived_repo.id])

        job =
          UserSecurityConfigurationJob.new(
            security_configuration_id: @security_configuration.id,
            user_id: @user.id,
            action: :apply,
            repository_ids: nil,
            override_existing_config: false,
          )

        job_progress_tracker = job.job_progress_tracker

        job_progress_tracker.start # Normally done when the job is enqueued.
        job.perform_now

        assert_enqueued_jobs 3, only: ApplySecurityConfigurationToRepositoryJob
        [@repo2, @repo4, @archived_repo].each do |repo|
          assert_enqueued_with(
            job: ApplySecurityConfigurationToRepositoryJob,
            args: [{
              actor_id: @user.id,
              repository_id: repo.id,
              security_configuration_id: @security_configuration.id,
              override_params: { skip_backfill_request: "1" },
              reason: nil,
            }]
          )
        end

        assert_predicate job_progress_tracker, :in_progress?
        assert_equal 3, job_progress_tracker.total_jobs
        assert_equal 3, job_progress_tracker.remaining_jobs
        assert_same_elements [@repo2.id, @repo4.id, @archived_repo.id], job_progress_tracker.repository_ids
      end

      test "applies to archived repos specified by repository_id" do
        job =
          UserSecurityConfigurationJob.new(
            security_configuration_id: @security_configuration.id,
            user_id: @user.id,
            action: :apply,
            repository_ids: [@repo1, @archived_repo.id],
            override_existing_config: true,
          )
        job_progress_tracker = job.job_progress_tracker

        job_progress_tracker.start # Normally done when the job is enqueued.
        job.perform_now

        assert_enqueued_jobs 2, only: ApplySecurityConfigurationToRepositoryJob
        assert_enqueued_with(
          job: ApplySecurityConfigurationToRepositoryJob,
          args: [{
            actor_id: @user.id,
            repository_id: @repo1.id,
            security_configuration_id: @security_configuration.id,
            override_params: { skip_backfill_request: "1" },
            reason: nil,
          }]
        )

        assert_predicate job_progress_tracker, :in_progress?
        assert_equal 2, job_progress_tracker.total_jobs
        assert_equal 2, job_progress_tracker.remaining_jobs
        assert_same_elements [@repo1.id, @archived_repo.id], job_progress_tracker.repository_ids
      end

      test "only increments the jobs progress tracker when a job is enqueued" do
        [@repo1, @repo3].each do |repo|
          create(:repository_security_configuration, state: :attached, repository: repo)
        end

        SecurityProductsEnablement::JobProgressTracker.any_instance.expects(:increment_jobs).times(3)
        SecurityProductsEnablement::JobProgressTracker.any_instance.expects(:finish).never

        assert_enqueued_jobs(3, only: ApplySecurityConfigurationToRepositoryJob) do
          UserSecurityConfigurationJob.perform_now(
            security_configuration_id: @security_configuration.id,
            user_id: @user.id,
            action: :apply,
            repository_ids: nil,
            override_existing_config: false,
          )
        end
      end

      test "marks the job progress tracker as finished if no jobs were enqueued" do
        [@repo1, @repo2, @repo3, @repo4, @archived_repo].each do |repo|
          create(:repository_security_configuration, state: :attached, repository: repo)
        end

        assert_no_enqueued_jobs(only: ApplySecurityConfigurationToRepositoryJob) do
          UserSecurityConfigurationJob.perform_now(
            security_configuration_id: @security_configuration.id,
            user_id: @user.id,
            action: :apply,
            repository_ids: nil,
            override_existing_config: false,
          )
        end

        job_progress_tracker = SecurityProductsEnablement::JobProgressTracker.new(@user.id)
        refute_predicate job_progress_tracker, :in_progress?
      end

      test "sets defaults when both options are present" do
        assert_changes -> { SecurityConfigurationDefault.count }, from: 0, to: 1 do
          UserSecurityConfigurationJob.perform_now(
            security_configuration_id: @security_configuration.id,
            user_id: @user.id,
            action: :apply,
            repository_ids: nil,
            override_existing_config: false,
            options: {
              default_for_new_public_repos: true,
              default_for_new_private_repos: true,
            }
          )
        end

        assert_equal 1, SecurityConfigurationDefault.where(
          target: @user,
          default_for_new_public_repos: true,
          default_for_new_private_repos: true
        ).count
      end

      test "sets defaults when only public repos option is present" do
        security_configuration = create(:security_configuration, target: @user)
        assert_changes -> { SecurityConfigurationDefault.count }, from: 0, to: 1 do
          UserSecurityConfigurationJob.perform_now(
            security_configuration_id: security_configuration.id,
            user_id: @user.id,
            action: :apply,
            repository_ids: nil,
            override_existing_config: false,
            options: {
              default_for_new_public_repos: true,
            }
          )
        end

        assert_equal 1, SecurityConfigurationDefault.where(
          target: @user,
          security_configuration_id: security_configuration.id,
          default_for_new_public_repos: true,
          default_for_new_private_repos: false
        ).count
      end

      test "sets defaults when only private repos option is present" do
        assert_changes -> { SecurityConfigurationDefault.count }, from: 0, to: 1 do
          UserSecurityConfigurationJob.perform_now(
            security_configuration_id: @security_configuration.id,
            user_id: @user.id,
            action: :apply,
            repository_ids: nil,
            override_existing_config: false,
            options: {
              default_for_new_private_repos: true,
            }
          )
        end

        assert_equal 1, SecurityConfigurationDefault.where(
          target: @user,
          default_for_new_public_repos: false,
          default_for_new_private_repos: true
        ).count
      end

      test "does not set defaults when both options are absent" do
        assert_no_changes -> { SecurityConfigurationDefault.count } do
          UserSecurityConfigurationJob.perform_now(
            security_configuration_id: @security_configuration.id,
            user_id: @user.id,
            action: :apply,
            repository_ids: nil,
            override_existing_config: false,
            options: {}
          )
        end
      end

      test "does not set defaults when options are falsey" do
        assert_no_changes -> { SecurityConfigurationDefault.count } do
          UserSecurityConfigurationJob.perform_now(
            security_configuration_id: @security_configuration.id,
            user_id: @user.id,
            action: :apply,
            repository_ids: nil,
            override_existing_config: false,
            options: {
              default_for_new_public_repos: false,
              default_for_new_private_repos: nil,
            }
          )
        end
      end
    end

    context "updating a configuration" do
      test "enqueues jobs to update repositories attached to the configuration" do
        configuration = create(:security_configuration, target: @user)

        create(:repository_security_configuration, state: :attached, repository: @repo1, security_configuration: configuration)
        create(:repository_security_configuration, state: :attached, repository: @repo3, security_configuration: configuration)

        create(:repository_security_configuration, state: :removed, repository: @repo2, security_configuration: configuration)
        create(:repository_security_configuration, state: :failed, repository: @repo4, security_configuration: configuration)

        assert_enqueued_jobs(2, only: ApplySecurityConfigurationToRepositoryJob) do
          UserSecurityConfigurationJob.perform_now(
            security_configuration_id: configuration.id,
            user_id: @user.id,
            repository_ids: nil,
            action: :update
          )
        end

        [@repo1, @repo3].each do |repo|
          assert_enqueued_with(
            job: ApplySecurityConfigurationToRepositoryJob,
            args: [{
              actor_id: @user.id,
              repository_id: repo.id,
              security_configuration_id: configuration.id,
              override_params: {},
            }]
          )

          repo_config = RepositorySecurityConfiguration.find_by(repository: repo)
          refute_nil repo_config
          assert_predicate repo_config, :updating?
        end
      end

      test "enqueues jobs to update repositories that have the configuration enforced and the enforcement policy changes" do
        # Mimicking a configuration that was enforced, but is then changed to become not enforced
        configuration = create(:security_configuration, target: @user)
        create(:repository_security_configuration, state: :enforced, repository: @repo1, security_configuration: configuration)
        create(:repository_security_configuration, state: :enforced, repository: @repo3, security_configuration: configuration)
        create(:repository_security_configuration, state: :failed, repository: @repo4, security_configuration: configuration)

        assert_enqueued_jobs(2, only: ApplySecurityConfigurationToRepositoryJob) do
          UserSecurityConfigurationJob.perform_now(
            security_configuration_id: configuration.id,
            user_id: @user.id,
            repository_ids: nil,
            action: :update
          )
        end

        [@repo1, @repo3].each do |repo|
          assert_enqueued_with(
            job: ApplySecurityConfigurationToRepositoryJob,
            args: [{
              actor_id: @user.id,
              repository_id: repo.id,
              security_configuration_id: configuration.id,
              override_params: {},
            }]
          )

          repo_config = RepositorySecurityConfiguration.find_by(repository: repo)
          refute_nil repo_config
          assert_predicate repo_config, :updating?
        end
      end

      test "enqueues jobs to update repositories that have the GH config enforced" do
        create(:repository_security_configuration, state: :enforced, repository: @repo1, security_configuration: @security_configuration)
        create(:repository_security_configuration, state: :enforced, repository: @repo3, security_configuration: @security_configuration)
        create(:repository_security_configuration, state: :failed, repository: @repo4, security_configuration: @security_configuration)

        assert_enqueued_jobs(2, only: ApplySecurityConfigurationToRepositoryJob) do
          UserSecurityConfigurationJob.perform_now(
            security_configuration_id: @security_configuration.id,
            user_id: @user.id,
            repository_ids: nil,
            action: :update
          )
        end

        [@repo1, @repo3].each do |repo|
          assert_enqueued_with(
            job: ApplySecurityConfigurationToRepositoryJob,
            args: [{
              actor_id: @user.id,
              repository_id: repo.id,
              security_configuration_id: @security_configuration.id,
              override_params: {},
            }]
          )

          repo_config = RepositorySecurityConfiguration.find_by(repository: repo)
          refute_nil repo_config
          assert_predicate repo_config, :updating?
        end
      end

      test "enqueues jobs to update only repos belonging to the current user that are attached to the GH config" do
        create(:repository_security_configuration, state: :enforced, repository: @repo1, security_configuration: @security_configuration)
        create(:repository_security_configuration, state: :attached, repository: @repo3, security_configuration: @security_configuration)

        other_user = create(:verified_user)
        other_repo = create(:private_repository, owner: other_user)
        create(:repository_security_configuration, state: :attached, repository: other_repo, security_configuration: @security_configuration)

        assert_enqueued_jobs(2, only: ApplySecurityConfigurationToRepositoryJob) do
          UserSecurityConfigurationJob.perform_now(
            security_configuration_id: @security_configuration.id,
            user_id: @user.id,
            repository_ids: nil,
            action: :update
          )
        end

        [@repo1, @repo3].each do |repo|
          assert_enqueued_with(
            job: ApplySecurityConfigurationToRepositoryJob,
            args: [{
              actor_id: @user.id,
              repository_id: repo.id,
              security_configuration_id: @security_configuration.id,
              override_params: {},
            }]
          )
        end
      end

      test "no-ops for GitHub recommended configuration" do
        assert_no_enqueued_jobs do
          UserSecurityConfigurationJob.perform_now(
            security_configuration_id: @security_configuration.id,
            user_id: @user.id,
            repository_ids: nil,
            action: :update
          )
        end
      end

      test "marks the job progress tracker as finished if no jobs were enqueued" do
        configuration = create(:security_configuration, target: @user)

        assert_no_enqueued_jobs(only: ApplySecurityConfigurationToRepositoryJob) do
          UserSecurityConfigurationJob.perform_now(
            security_configuration_id: configuration.id,
            user_id: @user.id,
            repository_ids: nil,
            action: :update,
          )
        end

        job_progress_tracker = SecurityProductsEnablement::JobProgressTracker.new(@user.id)
        refute_predicate job_progress_tracker, :in_progress?
      end
    end

    context "detaching configurations" do
      test "removes the repository security configuration records for the given repos" do
        [@repo1, @repo2, @repo3, @repo4, @archived_repo].each do |repo|
          create(:repository_security_configuration, state: :attached, repository: repo, security_configuration: @security_configuration)
        end
        assert_equal 5, RepositorySecurityConfiguration.where(security_configuration: @security_configuration).count

        assert_changes -> { RepositorySecurityConfiguration.where(security_configuration: @security_configuration).count }, from: 5, to: 2 do
          UserSecurityConfigurationJob.perform_now(
            security_configuration_id: nil,
            user_id: @user.id,
            action: :detach,
            repository_ids: [@repo1.id, @repo3.id, @archived_repo.id],
          )
        end

        assert_nil RepositorySecurityConfiguration.find_by(repository: @repo1)
        assert_nil RepositorySecurityConfiguration.find_by(repository: @repo3)
        assert_nil RepositorySecurityConfiguration.find_by(repository: @archived_repo)
      end
    end

    context "retry conditions" do
      test "retries on dirty exit" do
        assert_retry_on_dirty_exit(
          job: UserSecurityConfigurationJob,
          args: [{
            security_configuration_id: @security_configuration.id,
            user_id: @user.id,
            actor_id: @user.id,
            repository_ids: nil,
            override_existing_config: false,
          }]
        )
      end

      test "retries on recoverable exceptions" do
        assert_retry_on_recoverable_exceptions(
          job: UserSecurityConfigurationJob,
          args: [{
            security_configuration_id: @security_configuration.id,
            user_id: @user.id,
            actor_id: @user.id,
            repository_ids: nil,
            override_existing_config: false,
          }]
        )
      end
    end

    def stub_autocodeql_methods
      GitHub.stubs(:actions_enabled?).returns(true)
      CodeScanning::Status.stubs(:mac_os_runner?).returns(true)
      CodeScanning::Status.stubs(:validate_prerequisites)
      CodeScanning::AutoCodeql.any_instance.expects(:enabled?).at_least_once.returns(false)
    end
  end
end
