# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class UpdateRepositorySponsorablesForGlobalRepoJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @org = create(:organization)
    @global_health_files_repo = create(:repository, owner: @org, name: Repository::GLOBAL_HEALTH_FILES_NAME,
      from_example: :funding_links)
  end

  if GitHub.sponsors_enabled?
    test "enqueues jobs for each repo owned by the same owner as the given global health repo" do
      other_repo1, other_repo2 = create_list(:repository, 2, owner: @org)

      assert_enqueued_with(
        job: UpdateRepositorySponsorablesForRepositoryJob,
        args: [{ repository_id: other_repo1.id }]
      ) do
        assert_enqueued_with(
          job: UpdateRepositorySponsorablesForRepositoryJob,
          args: [{ repository_id: other_repo2.id }]
        ) do
          UpdateRepositorySponsorablesForGlobalRepoJob.perform_now(repository_id: @global_health_files_repo.id)
        end
      end
    end

    test "enqueues no jobs when the global health repo's owner has no other repositories" do
      assert_equal [@global_health_files_repo], @org.repositories

      assert_no_enqueued_jobs(only: UpdateRepositorySponsorablesForRepositoryJob) do
        UpdateRepositorySponsorablesForGlobalRepoJob.perform_now(repository_id: @global_health_files_repo.id)
      end
    end

    test "enqueues no jobs when given a non-global health repo" do
      other_repo1, other_repo2 = create_list(:repository, 2, owner: @org)

      assert_no_enqueued_jobs(only: UpdateRepositorySponsorablesForRepositoryJob) do
        UpdateRepositorySponsorablesForGlobalRepoJob.perform_now(repository_id: other_repo1.id)
      end
    end

    test "does not enqueue job for inactive repo" do
      inactive_repo = create(:repository, owner: @org, active: false)

      assert_no_enqueued_jobs(only: UpdateRepositorySponsorablesForRepositoryJob) do
        UpdateRepositorySponsorablesForGlobalRepoJob.perform_now(repository_id: @global_health_files_repo.id)
      end
    end

    test "retries the job on dirty exit" do
      assert_retry_on_dirty_exit(job: UpdateRepositorySponsorablesForGlobalRepoJob,
        args: [{ repository: @global_health_files_repo }])
    end
  else
    test "no-op when Sponsors is disabled" do
      other_repo1, other_repo2 = create_list(:repository, 2, owner: @org)

      assert_no_enqueued_jobs(only: UpdateRepositorySponsorablesForRepositoryJob) do
        UpdateRepositorySponsorablesForGlobalRepoJob.perform_now(repository_id: @global_health_files_repo.id)
      end
    end
  end
end
