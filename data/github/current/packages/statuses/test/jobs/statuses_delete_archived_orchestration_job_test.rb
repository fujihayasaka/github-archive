# typed: true
# frozen_string_literal: true

require "test_helper"

class StatusesDeleteArchivedOrchestrationJobTest < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    @repo = create(:repository, from_example: :simple)
  end

  setup do
    GitHub.stubs(:actions_enabled?).returns(true)
    make_trusted_oauth_apps_owner
    @launch_app = create(:launch_integration)
    GitHub.stubs(:launch_github_app).returns(@launch_app)
    StatusesDeleteArchivedOrchestrationJob.any_instance.stubs(:peak_traffic_time?).returns(false)

    if GitHub.enterprise?
      GitHub.stubs(:checks_retention_enabled?).returns(true)
      GitHub.stubs(:checks_retention_archive_threshold).returns(400)
    end
  end

  test "deletes archived statuses that are at least 10 days old" do
    StatusesDeleteArchivedOrchestrationJob.any_instance.stubs(:parallel_count).returns(1)
    StatusesDeleteArchivedOrchestrationJob.any_instance.stubs(:offset_per_batch).returns(1) # 2 statuses per batch

    new_non_archived_status = create(:status, state: :success, repository: @repo)
    new_archived_status = create(:status, state: :success, repository: @repo, archived_at: DateTime.now)

    not_old_enough_archived_status = Timecop.travel(9.days.ago) do
      create(:status, state: :success, repository: @repo, archived_at: Time.now)
    end
    older_archived_status = Timecop.travel(11.days.ago) do
      create(:status, state: :success, repository: @repo, archived_at: Time.now)
    end
    old_not_archived_status_status = Timecop.travel(450.days.ago) do
      create(:status, state: :success, repository: @repo)
    end
    old_archived_status_status = Timecop.travel(450.days.ago) do
      create(:status, state: :success, repository: @repo, archived_at: Time.now)
    end

    perform_enqueued_jobs(only: [StatusesDeleteArchivedJob]) do
      StatusesDeleteArchivedOrchestrationJob.perform_now
    end

    assert new_non_archived_status.reload
    assert new_archived_status.reload
    assert not_old_enough_archived_status.reload
    assert_raises ActiveRecord::RecordNotFound do
      older_archived_status.reload
    end
    assert old_not_archived_status_status.reload
    assert_raises ActiveRecord::RecordNotFound do
      old_archived_status_status.reload
    end

    assert_dogstats_count_value 2, "checks.delete_archived_job.deleted", tags: ["model:status"]
  end

  test "enqueues correctly based off the batch size and parallel count" do
    StatusesDeleteArchivedOrchestrationJob.any_instance.stubs(:parallel_count).returns(3)
    StatusesDeleteArchivedOrchestrationJob.any_instance.stubs(:offset_per_batch).returns(1) # 2 statuses per batch

    b1 = Timecop.travel(13.days.ago) do
      s1 = create(:status, state: :success, repository: @repo, archived_at: Time.now)
      s2 = create(:status, state: :success, repository: @repo, archived_at: Time.now)
      [s1.updated_at, s2.updated_at, s1.id]
    end

    b2 = Timecop.travel(12.days.ago) do
      s1 = create(:status, state: :success, repository: @repo, archived_at: Time.now)
      s2 = create(:status, state: :success, repository: @repo, archived_at: Time.now)
      [s1.updated_at, s2.updated_at]
    end

    b3 = Timecop.travel(11.days.ago) do
      s1 = create(:status, state: :success, repository: @repo, archived_at: Time.now)
      s2 = create(:status, state: :success, repository: @repo, archived_at: Time.now)
      [s1.updated_at, s2.updated_at]
    end

    assert_enqueued_jobs 3, only: StatusesDeleteArchivedJob do
      StatusesDeleteArchivedOrchestrationJob.perform_now
    end

    assert_dogstats_count_value b1[2], "checks.orchestrate_status_deletion.start_id"
    assert_dogstats_count_value 3, "checks.orchestrate_status_deletion.enqueued_deletions"

    assert_enqueued_with job: StatusesDeleteArchivedJob, args: [{ updated_at_start: b1[0], updated_at_end: b1[1], concurrent_job_key: "statuses_delete_archived_job_0" }]
    assert_enqueued_with job: StatusesDeleteArchivedJob, args: [{ updated_at_start: b2[0], updated_at_end: b2[1], concurrent_job_key: "statuses_delete_archived_job_1" }]
    assert_enqueued_with job: StatusesDeleteArchivedJob, args: [{ updated_at_start: b3[0], updated_at_end: b3[1], concurrent_job_key: "statuses_delete_archived_job_2" }]

    assert kv("statuses_delete_archived_job_0").exists("statuses_delete_archived_job_0").value!
    assert kv("statuses_delete_archived_job_1").exists("statuses_delete_archived_job_1").value!
    assert kv("statuses_delete_archived_job_2").exists("statuses_delete_archived_job_2").value!
  end

  test "does not enqueue any jobs if a concurrency key for a previous job exists in KV" do
    StatusesDeleteArchivedOrchestrationJob.any_instance.stubs(:parallel_count).returns(3)
    StatusesDeleteArchivedOrchestrationJob.any_instance.stubs(:offset_per_batch).returns(1) # 2 statuses per batch

    b1 = Timecop.travel(13.days.ago) do
      s1 = create(:status, state: :success, repository: @repo, archived_at: Time.now)
      s2 = create(:status, state: :success, repository: @repo, archived_at: Time.now)
      [s1.updated_at, s2.updated_at, s1.id]
    end

    b2 = Timecop.travel(12.days.ago) do
      s1 = create(:status, state: :success, repository: @repo, archived_at: Time.now)
      s2 = create(:status, state: :success, repository: @repo, archived_at: Time.now)
      [s1.updated_at, s2.updated_at]
    end

    b3 = Timecop.travel(11.days.ago) do
      s1 = create(:status, state: :success, repository: @repo, archived_at: Time.now)
      s2 = create(:status, state: :success, repository: @repo, archived_at: Time.now)
      [s1.updated_at, s2.updated_at]
    end

    kv("statuses_delete_archived_job_1").set("statuses_delete_archived_job_1", "true")

    assert_enqueued_jobs 0, only: StatusesDeleteArchivedJob do
      StatusesDeleteArchivedOrchestrationJob.perform_now
    end

    assert_dogstats_increment 1, "checks.orchestrate_status_deletion.previous_deletions_not_finished"
    refute_dogstats_count "checks.orchestrate_status_deletion.enqueued_deletions"
  end

  def kv(job_key)
    Actions::KV.for_key(job_key)
  end
end
