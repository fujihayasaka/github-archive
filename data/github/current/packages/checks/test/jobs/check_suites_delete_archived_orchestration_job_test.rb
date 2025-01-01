# typed: true
# frozen_string_literal: true

require "test_helper"

class CheckSuitesDeleteArchivedOrchestrationJobTest < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    @repo = create(:repository, from_example: :simple)
  end

  setup do
    GitHub.stubs(:actions_enabled?).returns(true)
    make_trusted_oauth_apps_owner
    @launch_app = create(:launch_integration)
    GitHub.stubs(:launch_github_app).returns(@launch_app)
    CheckSuitesDeleteArchivedOrchestrationJob.any_instance.stubs(:peak_traffic_time?).returns(false)

    if GitHub.enterprise?
      GitHub.stubs(:checks_retention_enabled?).returns(true)
      GitHub.stubs(:checks_retention_archive_threshold).returns(400)
    end
  end

  test "deletes archived statuses that are at least 10 days old" do
    CheckSuitesDeleteArchivedOrchestrationJob.any_instance.stubs(:offset_per_batch).returns(1) # 2 check suites per batch

    new_non_archived_check_suite = CheckSuite.create(head_sha: SecureRandom.hex(20), repository_id: @repo.id, github_app_id: 1)
    new_archived_check_suite = CheckSuite.create(head_sha: SecureRandom.hex(20), repository_id: @repo.id, github_app_id: 1, archived_at: Time.now)
    not_old_enough_archived_check_suite = Timecop.travel(9.days.ago) do
      CheckSuite.create(head_sha: SecureRandom.hex(20), repository_id: @repo.id, github_app_id: 1, archived_at: Time.now)
    end
    older_archived_check_suite = Timecop.travel(11.days.ago) do
      CheckSuite.create(head_sha: SecureRandom.hex(20), repository_id: @repo.id, github_app_id: 1, archived_at: Time.now)
    end
    old_not_archived_check_suite = Timecop.travel(450.days.ago) do
      CheckSuite.create(head_sha: SecureRandom.hex(20), repository_id: @repo.id, github_app_id: 1)
    end
    old_archived_check_suite = Timecop.travel(450.days.ago) do
      CheckSuite.create(head_sha: SecureRandom.hex(20), repository_id: @repo.id, github_app_id: 1, archived_at: Time.now)
    end

    perform_enqueued_jobs(only: [CheckSuitesDeleteArchivedJob]) do
      CheckSuitesDeleteArchivedOrchestrationJob.perform_now
    end

    assert_dogstats_count_value 2, "checks.delete_archived_job.deleted", tags: ["model:checksuite"]

    assert new_non_archived_check_suite.reload
    assert new_archived_check_suite.reload
    assert not_old_enough_archived_check_suite.reload
    assert_raises ActiveRecord::RecordNotFound do
      older_archived_check_suite.reload
    end
    assert old_not_archived_check_suite.reload
    assert_raises ActiveRecord::RecordNotFound do
      old_archived_check_suite.reload
    end
  end

  test "enqueues correctly based off the batch size and parallel count" do
    CheckSuitesDeleteArchivedOrchestrationJob.any_instance.stubs(:parallel_count).returns(3)
    CheckSuitesDeleteArchivedOrchestrationJob.any_instance.stubs(:offset_per_batch).returns(1) # 2 check suites per batch

    # Creating Check suites without the factory method since those also create check runs afterwards and that causes the check suites updated_at timestamps to slightly change which introduces potential flakiness
    b1 = Timecop.travel(13.days.ago) do
      cs1 = CheckSuite.create(head_sha: SecureRandom.hex(20), repository_id: @repo.id, github_app_id: 1, archived_at: Time.now)
      cs2 = CheckSuite.create(head_sha: SecureRandom.hex(20), repository_id: @repo.id, github_app_id: 1, archived_at: Time.now)
      [cs1, cs2]
    end

    b2 = Timecop.travel(12.days.ago) do
      cs1 = CheckSuite.create(head_sha: SecureRandom.hex(20), repository_id: @repo.id, github_app_id: 1, archived_at: Time.now)
      cs2 = CheckSuite.create(head_sha: SecureRandom.hex(20), repository_id: @repo.id, github_app_id: 1, archived_at: Time.now)
      [cs1, cs2]
    end

    b3 = Timecop.travel(11.days.ago) do
      cs1 = CheckSuite.create(head_sha: SecureRandom.hex(20), repository_id: @repo.id, github_app_id: 1, archived_at: Time.now)
      cs2 = CheckSuite.create(head_sha: SecureRandom.hex(20), repository_id: @repo.id, github_app_id: 1, archived_at: Time.now)
      [cs1, cs2]
    end

    assert_enqueued_jobs 3, only: CheckSuitesDeleteArchivedJob do
      CheckSuitesDeleteArchivedOrchestrationJob.perform_now
    end

    assert_dogstats_count_value b1[0].id, "checks.orchestrate_check_suite_deletion.start_id"
    assert_dogstats_count_value 3, "checks.orchestrate_check_suite_deletion.enqueued_deletions"

    # reload the check suites that were created to ensure the correct updated_at timestamps
    assert_enqueued_with job: CheckSuitesDeleteArchivedJob, args: [{ updated_at_start: b1[0].updated_at, updated_at_end: b1[1].updated_at, concurrent_job_key: "check_suites_delete_archived_job_0" }]
    assert_enqueued_with job: CheckSuitesDeleteArchivedJob, args: [{ updated_at_start: b2[0].updated_at, updated_at_end: b2[1].updated_at, concurrent_job_key: "check_suites_delete_archived_job_1" }]
    assert_enqueued_with job: CheckSuitesDeleteArchivedJob, args: [{ updated_at_start: b3[0].updated_at, updated_at_end: b3[1].updated_at, concurrent_job_key: "check_suites_delete_archived_job_2" }]

    assert kv("check_suites_delete_archived_job_0").exists("check_suites_delete_archived_job_0").value!
    assert kv("check_suites_delete_archived_job_1").exists("check_suites_delete_archived_job_1").value!
    assert kv("check_suites_delete_archived_job_2").exists("check_suites_delete_archived_job_2").value!
  end

  test "does not enqueue any jobs if a concurrency key for a previous job exists in KV" do
    CheckSuitesDeleteArchivedOrchestrationJob.any_instance.stubs(:parallel_count).returns(3)
    CheckSuitesDeleteArchivedOrchestrationJob.any_instance.stubs(:offset_per_batch).returns(1) # 2 check suites per batch

    b1 = Timecop.travel(13.days.ago) do
      cs1 = create(:check_suite, :completed, :success, repository: @repo, archived_at: Time.now)
      cs2 = create(:check_suite, :completed, :success, repository: @repo, archived_at: Time.now)
      [cs1.updated_at, cs2.updated_at, cs1.id]
    end

    b2 = Timecop.travel(12.days.ago) do
      cs1 = create(:check_suite, :completed, :success, repository: @repo, archived_at: Time.now)
      cs2 = create(:check_suite, :completed, :success, repository: @repo, archived_at: Time.now)
      [cs1.updated_at, cs2.updated_at]
    end

    b3 = Timecop.travel(11.days.ago) do
      cs1 = create(:check_suite, :completed, :success, repository: @repo, archived_at: Time.now)
      cs2 = create(:check_suite, :completed, :success, repository: @repo, archived_at: Time.now)
      [cs1.updated_at, cs2.updated_at]
    end

    kv("check_suites_delete_archived_job_1").set("check_suites_delete_archived_job_1", "true")

    assert_enqueued_jobs 0, only: CheckSuitesDeleteArchivedJob do
      CheckSuitesDeleteArchivedOrchestrationJob.perform_now
    end

    assert_dogstats_increment 1, "checks.orchestrate_check_suite_deletion.previous_deletions_not_finished"
    refute_dogstats_count "checks.orchestrate_check_suite_deletion.enqueued_deletions"
  end

  def kv(job_key)
    Actions::KV.for_key(job_key)
  end
end
