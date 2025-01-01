# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventWorkflowJobEventTest < GitHub::TestCase
  include HookEventTestHelper

  fixtures do
    make_trusted_oauth_apps_owner
    GitHub.stubs(:launch_github_app).returns(create(:launch_integration))
    GitHub.stubs(:actions_enabled?).returns(true)
    @workflow_job_run = create(:check_run_for_actions_app).workflow_job_run
  end

  test "required attributes" do
    assert_event_required_attributes Hook::Event::WorkflowJobEvent, :action, :job_id
  end

  context "#workflow_job" do
    test "returns the job" do
      event = Hook::Event::WorkflowJobEvent.new action: :queued, job_id: @workflow_job_run.id
      assert_equal @workflow_job_run, event.workflow_job
    end
  end

  context "#target_repository" do
    test "returns the repo of the parent check suite" do
      event = Hook::Event::WorkflowJobEvent.new action: :queued, job_id: @workflow_job_run.id
      assert_equal @workflow_job_run.check_run.check_suite.repository, event.target_repository
    end
  end

  context "#actor" do
    test "returns the creator of the parent check suite" do
      event = Hook::Event::WorkflowJobEvent.new action: :queued, job_id: @workflow_job_run.id
      assert_equal @workflow_job_run.check_run.check_suite.creator, event.actor
    end
  end

  context "#initialize_primary_resource" do
    test "initializes the primary resource data" do
      # WorkFlowJob Initialised from primary_resource_data
      GitHub.flipper["prehydrate_primary_webhook_data_for_workflow_job"].enable
      event = Hook::Event::WorkflowJobEvent.new action: :queued, job_id: @workflow_job_run.id, primary_resource_data: @workflow_job_run.attributes
      refute_nil event.instance_variable_get(:@workflow_job)
      refute_nil event.workflow_job
      assert_equal @workflow_job_run, event.workflow_job
      refute_nil event.target_repository
      assert_equal @workflow_job_run.check_run.check_suite.repository, event.target_repository
      refute_nil event.actor
      assert_equal @workflow_job_run.check_run.check_suite.creator, event.actor

      # WorkflowJob Initialised from database
      GitHub.flipper["prehydrate_primary_webhook_data_for_workflow_job"].disable
      event = Hook::Event::WorkflowJobEvent.new action: :queued, job_id: @workflow_job_run.id, primary_resource_data: @workflow_job_run.attributes
      assert_nil event.instance_variable_get(:@workflow_job)
    end
  end

  context "metrics" do
    unless GitHub.enterprise?
      test "prehydration_workflow_run_queries" do
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

        # No SQL queries should be made if the prehydration feature flag is enabled
        GitHub.flipper["prehydrate_primary_webhook_data_for_workflow_job"].enable
        event = Hook::Event::WorkflowJobEvent.new action: :queued, job_id: @workflow_job_run.id, primary_resource_data: @workflow_job_run.attributes
        _ = event.workflow_job
        mysql_metrics = GitHub.dogstats.distributions("hook.event.prehydration_workflow_job_queries", tags: ["cluster:application_record/repositories_actions_checks"])
        assert_equal 0, mysql_metrics.length

        # SQL Queries should be made if the primary resource data is not provided
        GitHub.dogstats.reset
        event = Hook::Event::WorkflowJobEvent.new action: :queued, job_id: @workflow_job_run.id
        _ = event.workflow_job
        mysql_metrics = GitHub.dogstats.distributions("hook.event.prehydration_workflow_job_queries", tags: ["cluster:application_record/repositories_actions_checks"])
        refute_empty mysql_metrics
        assert_equal 1, mysql_metrics.length

        # SQL Queries should be made if the prehydration feature flag is disabled
        GitHub.dogstats.reset
        GitHub.flipper["prehydrate_primary_webhook_data_for_workflow_job"].disable
        event = Hook::Event::WorkflowJobEvent.new action: :queued, job_id: @workflow_job_run.id, primary_resource_data: @workflow_job_run.attributes
        _ = event.workflow_job
        mysql_metrics = GitHub.dogstats.distributions("hook.event.prehydration_workflow_job_queries", tags: ["cluster:application_record/repositories_actions_checks"])
        refute_empty mysql_metrics
        assert_equal 1, mysql_metrics.length
      end
    end
  end
end
