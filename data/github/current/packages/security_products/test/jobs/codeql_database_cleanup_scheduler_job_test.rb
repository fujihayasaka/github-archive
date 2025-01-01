# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class CodeqlDatabaseCleanupSchedulerJobTest < GitHub::TestCase
  fixtures do
    # Create a small number of repos and CodeQL databases.
    # Enough to demonstrate things but not enough to take ages to set up the tests.
    # In tests we can stub num_unique_repo_ids to be higher if needed.
    @repos = 10.times.map do
      create(:repository)
    end
    @codeql_dbs = @repos.map do |repo|
      create(:codeql_database, repository: repo)
    end
  end

  test "with <168 existing CodeQL DBs, scheduler creates one cleanup job each time it runs" do
    assert_enqueued_jobs(1, only: CodeqlDatabaseCleanupJob) do
      CodeqlDatabaseCleanupSchedulerJob.perform_now
    end
  end

  test "with >168 existing CodeQL DBs, scheduler creates multiple cleanup jobs each time it runs" do
    CodeqlDatabaseCleanupSchedulerJob.any_instance.stubs(:num_unique_repo_ids).returns(1000)
    assert_enqueued_jobs(6, only: CodeqlDatabaseCleanupJob) do
      CodeqlDatabaseCleanupSchedulerJob.perform_now
    end
  end

  test "If last processed repo KV value isn't set, start from the beginning" do
    CodeScanning::KV.store.del(CodeqlDatabaseCleanupSchedulerJob::LAST_REPO_ID_PROCESSED_KV_KEY)
    assert_enqueued_jobs(1, only: CodeqlDatabaseCleanupJob) do
      assert_enqueued_with(job: CodeqlDatabaseCleanupJob, args: [{ repository_id: @repos[0].id }]) do
        CodeqlDatabaseCleanupSchedulerJob.perform_now
      end
    end
    assert_equal @repos[0].id, CodeScanning::KV.store.get(CodeqlDatabaseCleanupSchedulerJob::LAST_REPO_ID_PROCESSED_KV_KEY).value { nil }.to_i
  end

  test "If last processed repo KV value is set, start from that point" do
    CodeScanning::KV.store.set(CodeqlDatabaseCleanupSchedulerJob::LAST_REPO_ID_PROCESSED_KV_KEY, @repos[3].id.to_s)
    assert_enqueued_jobs(1, only: CodeqlDatabaseCleanupJob) do
      assert_enqueued_with(job: CodeqlDatabaseCleanupJob, args: [{ repository_id: @repos[4].id }]) do
        CodeqlDatabaseCleanupSchedulerJob.perform_now
      end
    end
    assert_equal @repos[4].id, CodeScanning::KV.store.get(CodeqlDatabaseCleanupSchedulerJob::LAST_REPO_ID_PROCESSED_KV_KEY).value { nil }.to_i
  end

  test "If last processed repo is the last repo, start again from the beginning" do
    CodeScanning::KV.store.set(CodeqlDatabaseCleanupSchedulerJob::LAST_REPO_ID_PROCESSED_KV_KEY, @repos[9].id.to_s)
    assert_enqueued_jobs(1, only: CodeqlDatabaseCleanupJob) do
      assert_enqueued_with(job: CodeqlDatabaseCleanupJob, args: [{ repository_id: @repos[0].id }]) do
        CodeqlDatabaseCleanupSchedulerJob.perform_now
      end
    end
    assert_equal @repos[0].id, CodeScanning::KV.store.get(CodeqlDatabaseCleanupSchedulerJob::LAST_REPO_ID_PROCESSED_KV_KEY).value { nil }.to_i
  end
end
