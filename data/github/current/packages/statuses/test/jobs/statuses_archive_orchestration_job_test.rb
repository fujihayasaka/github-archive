# typed: true
# frozen_string_literal: true

require "test_helper"

class StatusesArchiveOrchestrationJobTest < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    @repo = create(:repository, from_example: :simple)
  end

  setup do
    GitHub.stubs(:actions_enabled?).returns(true)
    make_trusted_oauth_apps_owner
    @launch_app = create(:launch_integration)
    GitHub.stubs(:launch_github_app).returns(@launch_app)
    StatusesArchiveOrchestrationJob.any_instance.stubs(:peak_traffic_time?).returns(false)

    if GitHub.enterprise?
      GitHub.stubs(:checks_retention_enabled?).returns(true)
      GitHub.stubs(:checks_retention_archive_threshold).returns(400)
    end
  end

  test "archives statuses older than 400 days" do
    recent_status = create(:status, state: :success, repository: @repo)
    not_old_enough_status = Timecop.travel(399.days.ago) do
      create(:status, state: :success, repository: @repo)
    end
    old_status = Timecop.travel(401.days.ago) do
      create(:status, state: :success, repository: @repo)
    end

    perform_enqueued_jobs(only: [StatusesArchiveJob]) do
      StatusesArchiveOrchestrationJob.perform_now
    end

    refute recent_status.reload.is_archived
    refute not_old_enough_status.reload.is_archived
    assert old_status.reload.is_archived

    assert_dogstats_count_value 1, "checks.archivable.archived", tags: ["model:status"]
  end

  test "enqueues correctly based off the batch size and parallel count" do
    StatusesArchiveOrchestrationJob.any_instance.stubs(:parallel_count).returns(3)
    StatusesArchiveOrchestrationJob.any_instance.stubs(:offset_per_batch).returns(1) # 2 statuses per batch

    b1 = Timecop.travel(403.days.ago) do
      first_status = create(:status, state: :success, repository: @repo)
      second_status = create(:status, state: :success, repository: @repo)
      [first_status.updated_at, second_status.updated_at, first_status.id]
    end

    b2 = Timecop.travel(402.days.ago) do
      first_status = create(:status, state: :success, repository: @repo)
      second_status = create(:status, state: :success, repository: @repo)
      [first_status.updated_at, second_status.updated_at]
    end

    b3 = Timecop.travel(401.days.ago) do
      first_status = create(:status, state: :success, repository: @repo)
      second_status = create(:status, state: :success, repository: @repo)
      [first_status.updated_at, second_status.updated_at]
    end

    assert_enqueued_jobs 3, only: StatusesArchiveJob do
      StatusesArchiveOrchestrationJob.perform_now
    end

    assert_enqueued_with job: StatusesArchiveJob, args: [{ updated_at_start: b1[0], updated_at_end: b1[1], concurrent_job_key: "statuses_archive_job_0" }]
    assert_enqueued_with job: StatusesArchiveJob, args: [{ updated_at_start: b2[0], updated_at_end: b2[1], concurrent_job_key: "statuses_archive_job_1" }]
    assert_enqueued_with job: StatusesArchiveJob, args: [{ updated_at_start: b3[0], updated_at_end: b3[1], concurrent_job_key: "statuses_archive_job_2" }]

    assert kv("statuses_archive_job_0").exists("statuses_archive_job_0").value!
    assert kv("statuses_archive_job_1").exists("statuses_archive_job_1").value!
    assert kv("statuses_archive_job_2").exists("statuses_archive_job_2").value!

    assert_dogstats_count_value b1[2], "checks.orchestrate_status_archiving.start_id"
  end

  test "enqueues correctly based off the batch size and parallel count if offset search does not find anything" do
    StatusesArchiveOrchestrationJob.any_instance.stubs(:parallel_count).returns(3)
    StatusesArchiveOrchestrationJob.any_instance.stubs(:offset_per_batch).returns(1) # 2 statuses per batch

    b1 = Timecop.travel(403.days.ago) do
      first_status = create(:status, state: :success, repository: @repo)
      second_status = create(:status, state: :success, repository: @repo)
      [first_status.updated_at, second_status.updated_at, first_status.id]
    end

    b2 = Timecop.travel(402.days.ago) do
      # Creating only a single status so that .offset will return nothing
      first_status = create(:status, state: :success, repository: @repo)
      first_status.updated_at
    end

    assert_enqueued_jobs 2, only: StatusesArchiveJob do
      StatusesArchiveOrchestrationJob.perform_now
    end

    assert_enqueued_with job: StatusesArchiveJob, args: [{ updated_at_start: b1[0], updated_at_end: b1[1], concurrent_job_key: "statuses_archive_job_0" }]
    assert_enqueued_with job: StatusesArchiveJob, args: [{ updated_at_start: b2, updated_at_end: b2, concurrent_job_key: "statuses_archive_job_1" }]

    assert kv("statuses_archive_job_0").exists("statuses_archive_job_0").value!
    assert kv("statuses_archive_job_1").exists("statuses_archive_job_1").value!

    assert_dogstats_count_value b1[2], "checks.orchestrate_status_archiving.start_id"
  end

  test "does not enqueue any jobs if a concurrency key for a previous job exists in KV" do
    StatusesArchiveOrchestrationJob.any_instance.stubs(:parallel_count).returns(3)
    StatusesArchiveOrchestrationJob.any_instance.stubs(:records_per_batch).returns(2)

    b1 = Timecop.travel(403.days.ago) do
      first_status = create(:status, state: :success, repository: @repo)
      second_status = create(:status, state: :success, repository: @repo)
      [first_status.updated_at, second_status.updated_at]
    end

    b2 = Timecop.travel(402.days.ago) do
      first_status = create(:status, state: :success, repository: @repo)
      second_status = create(:status, state: :success, repository: @repo)
      [first_status.updated_at, second_status.updated_at]
    end

    b3 = Timecop.travel(401.days.ago) do
      first_status = create(:status, state: :success, repository: @repo)
      second_status = create(:status, state: :success, repository: @repo)
      [first_status.updated_at, second_status.updated_at]
    end

    kv("statuses_archive_job_0").set("statuses_archive_job_0", "true")

    assert_enqueued_jobs 0, only: StatusesArchiveJob do
      StatusesArchiveOrchestrationJob.perform_now
    end

    assert_dogstats_increment 1, "checks.orchestrate_status_archiving.previous_archivings_not_finished"
    refute_dogstats_count "checks.orchestrate_status_archiving.enqueued_archivings"
    refute_dogstats_count "checks.orchestrate_status_archiving.start_id"
  end

  test "does not enqueue any jobs and does not throw any exceptions if there are no statuses to archive" do
    StatusesArchiveOrchestrationJob.any_instance.stubs(:parallel_count).returns(3)
    StatusesArchiveOrchestrationJob.any_instance.stubs(:records_per_batch).returns(2)

    first_status = create(:status, state: :success, repository: @repo)
    second_status = create(:status, state: :success, repository: @repo)

    Timecop.travel(399.days.ago) do
      first_status = create(:status, state: :success, repository: @repo)
      second_status = create(:status, state: :success, repository: @repo)
    end

    assert_nothing_raised do
      assert_enqueued_jobs 0, only: StatusesArchiveJob do
        StatusesArchiveOrchestrationJob.perform_now
      end
    end

    refute_dogstats_count "checks.orchestrate_status_archiving.start_id"
  end

  def kv(job_key)
    Actions::KV.for_key(job_key)
  end
end
