# typed: true
# frozen_string_literal: true

require "test_helper"

class CheckStepsDeleteJobTest < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    @repo = create(:repository)

    @check_suite = create :check_suite, repository: @repo
    @check_run   = create :check_run, check_suite: @check_suite
  end

  setup do
    GitHub.stubs(:actions_enabled?).returns(true)
    make_trusted_oauth_apps_owner
    @launch_app = create(:launch_integration)
    GitHub.stubs(:launch_github_app).returns(@launch_app)
  end

  test "delete threshold is 400 days" do
    assert_equal 400.days, CheckStepsDeleteJob.delete_threshold_days
  end

  test "throws error if start_id is not provided" do
    assert_raises(ArgumentError) do
      CheckStepsDeleteJob.perform_now(start_id: nil, end_id: 10, concurrent_job_key: "check_steps_delete_job_0")
    end
  end

  test "throws error if end_id is not provided" do
    assert_raises(ArgumentError) do
      CheckStepsDeleteJob.perform_now(start_id: 1, end_id: nil, concurrent_job_key: "check_steps_delete_job_0")
    end
  end

  test "throws error if concurrent_job_key is not provided" do
    assert_raises(ArgumentError) do
      CheckStepsDeleteJob.perform_now(start_id: 1, end_id: 10, concurrent_job_key: nil)
    end
  end

  test "correctly deletes check steps older than 400 days" do
    recent_check_step = create(:check_step, name: "recent check step", check_run: @check_run, repository: @repo)
    not_old_enough_check_step = Timecop.travel(399.days.ago) do
      create(:check_step, name: "399 day old check step", check_run: @check_run, repository: @repo)
    end
    old_check_step = Timecop.travel(401.days.ago) do
      create(:check_step, name: "401 day old check step", check_run: @check_run, repository: @repo)
    end

    assert_nothing_raised do
      CheckStepsDeleteJob.perform_now(start_id: recent_check_step.id, end_id: old_check_step.id, concurrent_job_key: "check_steps_delete_job_0")
    end

    assert recent_check_step.reload
    assert not_old_enough_check_step.reload
    assert_raises ActiveRecord::RecordNotFound do
      assert old_check_step.reload
    end

    assert_dogstats_count_value 1, "checks.delete_check_steps_job.deleted"
  end

  test "does not delete anything if there are no steps older than 400 days" do
    first_check_step = create(:check_step, name: "oldest check step", check_run: @check_run, repository: @repo)
    15.times do |i|
      create(:check_step, name: "recent check step #{i}", check_run: @check_run, repository: @repo)
    end
    last_check_step = create(:check_step, name: "newest check step", check_run: @check_run, repository: @repo)

    assert_no_changes -> { CheckStep.where(repository_id: @repo.id).pluck(:id) } do
      CheckStepsDeleteJob.perform_now(start_id: first_check_step.id, end_id: last_check_step.id, concurrent_job_key: "check_steps_delete_job_0")
    end

    assert_dogstats_count_value 0, "checks.delete_check_steps_job.deleted"
  end

  test "deletes multiple records older than 400 days" do
    first_check_step = create(:check_step, name: "oldest check step", check_run: @check_run, repository: @repo)
    last_check_step = Timecop.travel(401.days.ago) do
      15.times do |i|
        create(:check_step, name: "recent check step #{i}", check_run: @check_run, repository: @repo)
      end
      create(:check_step, name: "newest check step", check_run: @check_run, repository: @repo)
    end

    assert_nothing_raised do
      CheckStepsDeleteJob.perform_now(start_id: first_check_step.id, end_id: last_check_step.id, concurrent_job_key: "check_steps_delete_job_0")
    end

    assert_dogstats_count_value 16, "checks.delete_check_steps_job.deleted"
    assert first_check_step.reload
    assert_raises ActiveRecord::RecordNotFound do
      assert last_check_step.reload
    end
  end

  test "does not delete anything if there no records found within range" do
    recent_step = create(:check_step, name: "recent check step", check_run: @check_run, repository: @repo)
    last_check_step = Timecop.travel(401.days.ago) do
      15.times do |i|
        create(:check_step, name: "recent check step #{i}", check_run: @check_run, repository: @repo)
      end
      create(:check_step, name: "newest check step", check_run: @check_run, repository: @repo)
    end
    start_id = recent_step.id
    end_id = last_check_step.id

    # clear out any existing steps
    CheckStep.where(repository_id: @repo.id).delete_all
    assert_equal 0, @check_run.steps.count

    assert_nothing_raised do
      CheckStepsDeleteJob.perform_now(start_id: start_id, end_id: end_id, concurrent_job_key: "check_steps_delete_job_0")
    end
    assert_dogstats_count_value 0, "checks.delete_check_steps_job.deleted"
  end

  test "clears concurrency key at the end of each job" do
    concurrency_key = "check_steps_delete_job_0"

    new_check_step = create(:check_step, name: "new check step", check_run: @check_run, repository: @repo)
    old_check_step = Timecop.travel(401.days.ago) do
      create(:check_step, name: "old check step", check_run: @check_run, repository: @repo)
    end

    kv_set(concurrency_key, "true")

    assert kv_exists?(concurrency_key)
    assert_nothing_raised do
      CheckStepsDeleteJob.perform_now(start_id: new_check_step.id, end_id: old_check_step.id, concurrent_job_key: concurrency_key)
    end

    refute kv_exists?(concurrency_key)
    assert_dogstats_count_value 1, "checks.delete_check_steps_job.deleted"
    assert new_check_step.reload
    assert_raises ActiveRecord::RecordNotFound do
      assert old_check_step.reload
    end
  end

  def kv_exists?(key)
    Actions::KV.for_key(key).exists(key).value!
  end

  def kv_set(key, value)
    Actions::KV.for_key(key).set(key, value)
  end
end
