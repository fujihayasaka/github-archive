# typed: true
# frozen_string_literal: true
require "test_helper"

class GhesActionsJobExecutionTest < GitHub::TestCase
  test "create_does_not_raise" do
    assert_nothing_raised do
      self.class.create_job_execution!
    end
  end

  test "create_does_not_allow_duplicate_event_id" do
    uuid = SimpleUUID::UUID.new
    self.class.create_job_execution!(uuid)

    assert_raises ActiveRecord::RecordNotUnique do
      self.class.create_job_execution!(uuid)
    end
  end

  test "created_between" do
    self.class.create_job_execution!(SimpleUUID::UUID.new, 2.days.ago)
    self.class.create_job_execution!(SimpleUUID::UUID.new, 1.week.ago)

    results = GhesActionsJobExecution.created_between(3.days.ago, 1.day.ago)
    assert_equal(1, results.count)
  end

  def self.create_job_execution!(event_id = SimpleUUID::UUID.new, created_at = Time.now)
    GhesActionsJobExecution.create!(
        event_id: event_id,
        invoking_event_type: "push",
        workflow_repository_id: 1,
        workflow_repository_global_id: "1",
        workflow_repository_visibility: "public",
        workflow_build_id: 1,
        job_id: "1",
        job_runtime: "docker",
        job_runtime_version: "1.0.0",
        job_check_run_id: 1,
        started_at: Time.now,
        finished_at: Time.now,
        runner_properties: { "foo": "bar" },
        runner_type: "foo",
        job_execution_billable_ms: 1,
        job_check_run_conclusion: "foo",
        organization_id: 1,
        created_at: created_at)
  end
end
