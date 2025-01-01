# typed: true
# frozen_string_literal: true

require "test_helper"

class CheckSuitesArchiveOrchestrationJobTest < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    @repo = create(:repository, from_example: :simple)
  end

  setup do
    GitHub.stubs(:actions_enabled?).returns(true)
    make_trusted_oauth_apps_owner
    @launch_app = create(:launch_integration)
    GitHub.stubs(:launch_github_app).returns(@launch_app)
    CheckSuitesArchiveOrchestrationJob.any_instance.stubs(:peak_traffic_time?).returns(false)

    if GitHub.enterprise?
      GitHub.stubs(:checks_retention_enabled?).returns(true)
      GitHub.stubs(:checks_retention_archive_threshold).returns(400)
    end
  end

  def travel_to_archive_time(&block)
    outside_retention = (ChecksJobUtility::DEFAULT_MAX_ARCHIVE_THRESHOLD_IN_DAYS + 1.day).ago
    Timecop.freeze(outside_retention) do
      block.call
    end
  end

  test "archives check suites older than 400 days" do
    old_check_suite = Timecop.travel(401.days.ago) do
      create(:check_suite, :completed, :success, repository: @repo)
    end
    not_old_enough_check_suite = Timecop.travel(399.days.ago) do
      create(:check_suite, :completed, :success, repository: @repo)
    end
    new_archived_check_suite = create(:check_suite, :completed, :success, repository: @repo, archived_at: DateTime.now)
    archived_time = new_archived_check_suite.archived_at
    new_non_archived_check_suite = create(:check_suite, :completed, :success, repository: @repo)

    perform_enqueued_jobs(only: [CheckSuitesArchiveJob]) do
      CheckSuitesArchiveOrchestrationJob.perform_now
    end

    old_check_suite.reload
    not_old_enough_check_suite.reload
    new_archived_check_suite.reload
    new_non_archived_check_suite.reload

    assert old_check_suite.is_archived
    refute not_old_enough_check_suite.is_archived
    assert_equal archived_time, new_archived_check_suite.archived_at
    refute new_non_archived_check_suite.is_archived

    assert_dogstats_count_value 1, "checks.archivable.archived", tags: ["model:checksuite"]
  end

  test "enqueues correctly based off the batch size and parallel count" do
    CheckSuitesArchiveOrchestrationJob.any_instance.stubs(:parallel_count).returns(3)
    CheckSuitesArchiveOrchestrationJob.any_instance.stubs(:offset_per_batch).returns(1) # 2 check_suites per batch

    b1 = Timecop.travel(403.days.ago) do
      first_cs = create(:check_suite, :completed, :success, repository: @repo)
      second_cs = create(:check_suite, :completed, :success, repository: @repo)
      [first_cs.updated_at, second_cs.updated_at, first_cs.id]
    end

    b2 = Timecop.travel(402.days.ago) do
      first_cs = create(:check_suite, :completed, :success, repository: @repo)
      second_cs = create(:check_suite, :completed, :success, repository: @repo)
      [first_cs.updated_at, second_cs.updated_at]
    end

    b3 = Timecop.travel(401.days.ago) do
      first_cs = create(:check_suite, :completed, :success, repository: @repo)
      second_cs = create(:check_suite, :completed, :success, repository: @repo)
      [first_cs.updated_at, second_cs.updated_at]
    end

    assert_enqueued_jobs 3, only: CheckSuitesArchiveJob do
      CheckSuitesArchiveOrchestrationJob.perform_now
    end

    assert_dogstats_count_value b1[2], "checks.orchestrate_check_suites_archiving.start_id"
    assert_dogstats_count_value 3, "checks.orchestrate_check_suite_archiving.enqueued_archivings"

    assert_enqueued_with job: CheckSuitesArchiveJob, args: [{ updated_at_start: b1[0], updated_at_end: b1[1], concurrent_job_key: "check_suites_archive_job_0" }]
    assert_enqueued_with job: CheckSuitesArchiveJob, args: [{ updated_at_start: b2[0], updated_at_end: b2[1], concurrent_job_key: "check_suites_archive_job_1" }]
    assert_enqueued_with job: CheckSuitesArchiveJob, args: [{ updated_at_start: b3[0], updated_at_end: b3[1], concurrent_job_key: "check_suites_archive_job_2" }]

    assert kv_exists("check_suites_archive_job_0").value!
    assert kv_exists("check_suites_archive_job_1").value!
    assert kv_exists("check_suites_archive_job_2").value!
  end

  test "enqueues correctly based off the batch size and parallel count if offset search does not find anything" do
    CheckSuitesArchiveOrchestrationJob.any_instance.stubs(:parallel_count).returns(3)
    CheckSuitesArchiveOrchestrationJob.any_instance.stubs(:offset_per_batch).returns(1) # 2 check_suites per batch

    b1 = Timecop.travel(403.days.ago) do
      first_cs = create(:check_suite, :completed, :success, repository: @repo)
      second_cs = create(:check_suite, :completed, :success, repository: @repo)
      [first_cs.updated_at, second_cs.updated_at, first_cs.id]
    end

    b2 = Timecop.travel(402.days.ago) do
      # Creating only a single check suite so that .offset will return nothing
      cs = create(:check_suite, :completed, :success, repository: @repo)
      cs.updated_at
    end

    assert_enqueued_jobs 2, only: CheckSuitesArchiveJob do
      CheckSuitesArchiveOrchestrationJob.perform_now
    end

    assert_dogstats_count_value b1[2], "checks.orchestrate_check_suites_archiving.start_id"

    assert_enqueued_with job: CheckSuitesArchiveJob, args: [{ updated_at_start: b1[0], updated_at_end: b1[1], concurrent_job_key: "check_suites_archive_job_0" }]
    assert_enqueued_with job: CheckSuitesArchiveJob, args: [{ updated_at_start: b2, updated_at_end: b2, concurrent_job_key: "check_suites_archive_job_1" }]

    assert kv_exists("check_suites_archive_job_0").value!
    assert kv_exists("check_suites_archive_job_1").value!
  end

  test "does not enqueue any jobs if a concurrency key for a previous job exists in KV" do
    CheckSuitesArchiveOrchestrationJob.any_instance.stubs(:parallel_count).returns(3)
    CheckSuitesArchiveOrchestrationJob.any_instance.stubs(:records_per_batch).returns(2)

    b1 = travel_to_archive_time do
      first_cs = create(:check_suite, :completed, :success, repository: @repo)
      second_cs = create(:check_suite, :completed, :success, repository: @repo)
      [first_cs.updated_at, second_cs.updated_at]
    end

    b2 = travel_to_archive_time do
      first_cs = create(:check_suite, :completed, :success, repository: @repo)
      second_cs = create(:check_suite, :completed, :success, repository: @repo)
      [first_cs.updated_at, second_cs.updated_at]
    end

    b3 = travel_to_archive_time do
      first_cs = create(:check_suite, :completed, :success, repository: @repo)
      second_cs = create(:check_suite, :completed, :success, repository: @repo)
      [first_cs.updated_at, second_cs.updated_at]
    end

    kv_set("check_suites_archive_job_1", "true")

    assert_enqueued_jobs 0, only: CheckSuitesArchiveJob do
      CheckSuitesArchiveOrchestrationJob.perform_now
    end

    assert_dogstats_increment 1, "checks.orchestrate_check_suite_archiving.previous_archivings_not_finished"
    refute_dogstats_count "checks.orchestrate_check_suites_archiving.enqueued_archivings"
  end

  test "does not enqueue any jobs and does not throw any exceptions if there are no check suites to archive" do
    CheckSuitesArchiveOrchestrationJob.any_instance.stubs(:parallel_count).returns(3)
    CheckSuitesArchiveOrchestrationJob.any_instance.stubs(:records_per_batch).returns(2)

    first_cs = create(:check_suite, :completed, :success, repository: @repo)
    second_cs = create(:check_suite, :completed, :success, repository: @repo)

    Timecop.travel(399.days.ago) do
      first_cs = create(:check_suite, :completed, :success, repository: @repo)
      second_cs = create(:check_suite, :completed, :success, repository: @repo)
    end

    assert_nothing_raised do
      assert_enqueued_jobs 0, only: CheckSuitesArchiveJob do
        CheckSuitesArchiveOrchestrationJob.perform_now
      end
    end

    refute_dogstats_count "checks.orchestrate_check_suites_archiving.start_id"
  end

  def kv_set(job_key, value)
    Actions::KV.for_key(job_key).set(job_key, value)
  end

  def kv_exists(job_key)
    Actions::KV.for_key(job_key).exists(job_key)
  end
end
