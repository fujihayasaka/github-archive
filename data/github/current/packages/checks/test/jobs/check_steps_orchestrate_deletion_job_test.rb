# typed: true
# frozen_string_literal: true

require "test_helper"

class CheckStepsOrchestrateDeletionJobTest < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    @repo = create(:repository, from_example: :simple)

    @check_suite = create :check_suite, repository: @repo
    @check_run   = create :check_run, check_suite: @check_suite
  end

  setup do
    GitHub.stubs(:actions_enabled?).returns(true)
    make_trusted_oauth_apps_owner
    @launch_app = create(:launch_integration)
    GitHub.stubs(:launch_github_app).returns(@launch_app)
    CheckStepsOrchestrateDeletionJob.any_instance.stubs(:peak_traffic_time?).returns(false)
  end

  def travel_to_deletion(&block)
    outside_deletion = (401.days).ago
    Timecop.freeze(outside_deletion) do
      block.call
    end
  end

  if GitHub.multi_tenant_enterprise?
    test "does not delete check_steps older than 400 days in proxima" do
      recent_check_step = create(:check_step, name: "recent check step", check_run: @check_run, repository: @repo)
      not_old_enough_check_step = Timecop.travel(399.days.ago) do
        create(:check_step, name: "399 day old check step", check_run: @check_run, repository: @repo)
      end
      old_check_step = Timecop.travel(401.days.ago) do
        create(:check_step, name: "401 day old check step", check_run: @check_run, repository: @repo)
      end

      perform_enqueued_jobs(only: [CheckStepsDeleteJob]) do
        CheckStepsOrchestrateDeletionJob.perform_now
      end

      assert CheckStep.exists?(recent_check_step.id)
      assert CheckStep.exists?(not_old_enough_check_step.id)
      assert CheckStep.exists?(old_check_step.id)
    end
  else
    test "deletes check_steps older than 400 days" do
      recent_check_step = create(:check_step, name: "recent check step", check_run: @check_run, repository: @repo)
      not_old_enough_check_step = Timecop.travel(399.days.ago) do
        create(:check_step, name: "399 day old check step", check_run: @check_run, repository: @repo)
      end
      old_check_step = Timecop.travel(401.days.ago) do
        create(:check_step, name: "401 day old check step", check_run: @check_run, repository: @repo)
      end

      perform_enqueued_jobs(only: [CheckStepsDeleteJob]) do
        CheckStepsOrchestrateDeletionJob.perform_now
      end

      assert recent_check_step.reload
      assert not_old_enough_check_step.reload
      assert_raises ActiveRecord::RecordNotFound do
        assert old_check_step.reload
      end

      assert_dogstats_count_value 1, "checks.delete_check_steps_job.deleted"
    end

    test "enqueues correctly based off the batch size and parallel count" do
      CheckStepsOrchestrateDeletionJob.any_instance.stubs(:parallel_count).returns(5)
      CheckStepsOrchestrateDeletionJob.any_instance.stubs(:records_per_batch).returns(2)

      b1 = travel_to_deletion do
        first_step = create(:check_step, name: "batch 1 start", check_run: @check_run, repository: @repo)
        second_step = create(:check_step, name: "batch 1 end", check_run: @check_run, repository: @repo)
        [first_step.id, second_step.id]
      end

      b2 = travel_to_deletion do
        first_step = create(:check_step, name: "batch 2 start", check_run: @check_run, repository: @repo)
        second_step = create(:check_step, name: "batch 2 end", check_run: @check_run, repository: @repo)
        [first_step.id, second_step.id]
      end

      b3 = travel_to_deletion do
        first_step = create(:check_step, name: "batch 3 start", check_run: @check_run, repository: @repo)
        second_step = create(:check_step, name: "batch 3 end", check_run: @check_run, repository: @repo)
        [first_step.id, second_step.id]
      end

      b4 = travel_to_deletion do
        first_step = create(:check_step, name: "batch 4 start", check_run: @check_run, repository: @repo)
        second_step = create(:check_step, name: "batch 4 end", check_run: @check_run, repository: @repo)
        [first_step.id, second_step.id]
      end

      b5 = travel_to_deletion do
        first_step = create(:check_step, name: "batch 5 start", check_run: @check_run, repository: @repo)
        second_step = create(:check_step, name: "batch 5 end", check_run: @check_run, repository: @repo)
        [first_step.id, second_step.id]
      end

      assert_enqueued_jobs 5, only: CheckStepsDeleteJob do
        CheckStepsOrchestrateDeletionJob.perform_now
      end

      assert_dogstats_count_value b1.first, "checks.orchestrate_check_steps_deletion.start_id"
      assert_dogstats_count_value 5, "checks.orchestrate_check_steps_deletion.enqueued_deletions"

      assert_enqueued_with job: CheckStepsDeleteJob, args: [{ start_id: b1.first, end_id: b1.last, concurrent_job_key: "check_steps_delete_job_0" }]
      assert_enqueued_with job: CheckStepsDeleteJob, args: [{ start_id: b2.first, end_id: b2.last, concurrent_job_key: "check_steps_delete_job_1" }]
      assert_enqueued_with job: CheckStepsDeleteJob, args: [{ start_id: b3.first, end_id: b3.last, concurrent_job_key: "check_steps_delete_job_2" }]
      assert_enqueued_with job: CheckStepsDeleteJob, args: [{ start_id: b4.first, end_id: b4.last, concurrent_job_key: "check_steps_delete_job_3" }]
      assert_enqueued_with job: CheckStepsDeleteJob, args: [{ start_id: b5.first, end_id: b5.last, concurrent_job_key: "check_steps_delete_job_4" }]

      assert kv_exists?("check_steps_delete_job_0")
      assert kv_exists?("check_steps_delete_job_1")
      assert kv_exists?("check_steps_delete_job_2")
      assert kv_exists?("check_steps_delete_job_3")
      assert kv_exists?("check_steps_delete_job_4")
    end

    test "enqueues correctly based off the batch size and parallel count at the same time" do
      CheckStepsOrchestrateDeletionJob.any_instance.stubs(:parallel_count).returns(5)
      CheckStepsOrchestrateDeletionJob.any_instance.stubs(:records_per_batch).returns(2)

      b1 = travel_to_deletion do
        first_step = create(:check_step, name: "batch 1 start", check_run: @check_run, repository: @repo)
        second_step = create(:check_step, name: "batch 1 end", check_run: @check_run, repository: @repo)
        [first_step.id, second_step.id]
      end

      b2 = travel_to_deletion do
        first_step = create(:check_step, name: "batch 2 start", check_run: @check_run, repository: @repo)
        second_step = create(:check_step, name: "batch 2 end", check_run: @check_run, repository: @repo)
        [first_step.id, second_step.id]
      end

      b3 = travel_to_deletion do
        first_step = create(:check_step, name: "batch 3 start", check_run: @check_run, repository: @repo)
        second_step = create(:check_step, name: "batch 3 end", check_run: @check_run, repository: @repo)
        [first_step.id, second_step.id]
      end

      b4 = travel_to_deletion do
        first_step = create(:check_step, name: "batch 4 start", check_run: @check_run, repository: @repo)
        second_step = create(:check_step, name: "batch 4 end", check_run: @check_run, repository: @repo)
        [first_step.id, second_step.id]
      end

      b5 = travel_to_deletion do
        first_step = create(:check_step, name: "batch 5 start", check_run: @check_run, repository: @repo)
        second_step = create(:check_step, name: "batch 5 end", check_run: @check_run, repository: @repo)
        [first_step.id, second_step.id]
      end

      assert_enqueued_jobs 5, only: CheckStepsDeleteJob do
        CheckStepsOrchestrateDeletionJob.perform_now
      end

      assert_dogstats_count_value b1.first, "checks.orchestrate_check_steps_deletion.start_id"
      assert_dogstats_count_value 5, "checks.orchestrate_check_steps_deletion.enqueued_deletions"

      assert_enqueued_with job: CheckStepsDeleteJob, args: [{ start_id: b1.first, end_id: b1.last, concurrent_job_key: "check_steps_delete_job_0" }]
      assert_enqueued_with job: CheckStepsDeleteJob, args: [{ start_id: b2.first, end_id: b2.last, concurrent_job_key: "check_steps_delete_job_1" }]
      assert_enqueued_with job: CheckStepsDeleteJob, args: [{ start_id: b3.first, end_id: b3.last, concurrent_job_key: "check_steps_delete_job_2" }]
      assert_enqueued_with job: CheckStepsDeleteJob, args: [{ start_id: b4.first, end_id: b4.last, concurrent_job_key: "check_steps_delete_job_3" }]
      assert_enqueued_with job: CheckStepsDeleteJob, args: [{ start_id: b5.first, end_id: b5.last, concurrent_job_key: "check_steps_delete_job_4" }]
    end

    test "does not enqueue any jobs if a concurrency key for a previous job exists in KV" do
      CheckStepsOrchestrateDeletionJob.any_instance.stubs(:parallel_count).returns(2)
      CheckStepsOrchestrateDeletionJob.any_instance.stubs(:records_per_batch).returns(2)

      b1 = travel_to_deletion do
        first_step = create(:check_step, name: "batch 1 start", check_run: @check_run, repository: @repo)
        second_step = create(:check_step, name: "batch 1 end", check_run: @check_run, repository: @repo)
        [first_step.id, second_step.id]
      end

      b2 = travel_to_deletion do
        first_step = create(:check_step, name: "batch 2 start", check_run: @check_run, repository: @repo)
        second_step = create(:check_step, name: "batch 2 end", check_run: @check_run, repository: @repo)
        [first_step.id, second_step.id]
      end

      kv_set("check_steps_delete_job_0", "true") # rubocop:todo GitHub/DoNotUseGlobalKv

      assert_enqueued_jobs 0, only: CheckStepsDeleteJob do
        CheckStepsOrchestrateDeletionJob.perform_now
      end

      assert_dogstats_increment 1, "checks.orchestrate_check_steps_deletion.previous_deletions_not_finished"
      refute_dogstats_count "checks.orchestrate_check_steps_deletion.enqueued_deletions"
    end
  end

  def kv_exists?(key)
    Actions::KV.for_key(key).exists(key).value!
  end

  def kv_set(key, value)
    Actions::KV.for_key(key).set(key, value)
  end
end
