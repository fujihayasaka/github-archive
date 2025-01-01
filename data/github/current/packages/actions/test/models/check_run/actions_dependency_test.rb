# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/launch/checks_helper"
require "test_helpers/actions_results/checks_helper"

class CheckRunActionsDependencyTest < GitHub::TestCase
  include Launch::ChecksHelper
  include ActionsResults::ChecksHelper

  setup do
    GitHub.stubs(:actions_enabled?).returns(true)
  end

  fixtures do
    make_trusted_oauth_apps_owner
    @org = create(:organization)
    @repo = create(:repository, owner: @org)
    @check_suite = create(:check_suite_for_actions_app, :in_progress, head_repository: @repo, repository: @repo)
  end

  context "#steps_from_launch" do
    test "gets step information from launch" do
      in_progress_check_run = create :check_run_for_actions_app, :with_steps, name: "lint-check", check_suite: @check_suite, status: "in_progress"

      mock_steps_for_change_id(repo: @repo, check_run: in_progress_check_run, change_id: 1337)

      expected_step = in_progress_check_run.steps.first
      actual_step = in_progress_check_run.steps_from_launch(1337).first

      assert_equal expected_step.name, actual_step.name
      assert_equal expected_step.number, actual_step.number
      assert_equal expected_step.status, actual_step.status
      assert_equal expected_step.conclusion, actual_step.conclusion
      assert_equal expected_step.started_at, actual_step.started_at
      assert_equal expected_step.completed_at, actual_step.completed_at
    end

    test "gets step information from launch lab" do
      launch_lab_app = GitHub.launch_lab_github_app || create(:launch_lab_integration)
      GitHub.stubs(:launch_lab_github_app).returns(launch_lab_app)
      lab_check_suite = create(
        :check_suite_for_actions_app,
        github_app: launch_lab_app,
        repository: @repo,
        workflow_file_path: ".github/workflows-lab/test.yml"
      )

      in_progress_check_run = create :check_run_for_actions_app, :with_steps, name: "lint-check", check_suite: lab_check_suite, status: "in_progress"

      mock_steps_for_change_id(lab: true, repo: @repo, check_run: in_progress_check_run, change_id: 1337)

      expected_step = in_progress_check_run.steps.first
      actual_step = in_progress_check_run.steps_from_launch(1337).first

      assert_equal expected_step.name, actual_step.name
      assert_equal expected_step.number, actual_step.number
      assert_equal expected_step.status, actual_step.status
      assert_equal expected_step.conclusion, actual_step.conclusion
      assert_equal expected_step.started_at, actual_step.started_at
      assert_equal expected_step.completed_at, actual_step.completed_at
    end

    test "does not call Launch if non-actions check run" do
      check_run = create :check_run, :with_steps, name: "lint-check", check_suite: @check_suite, status: "in_progress"

      Launch::Twirp::ChecksClient.any_instance.expects(:rpc).with(:StepsFromChangeID, anything).never

      assert_empty check_run.steps_from_launch
    end
  end

  context "#steps_from_results" do
    test "correct steps for execution" do
      check_suite = create :check_suite_for_actions_app, :success
      check_run = create :check_run_for_actions_app, :success, check_suite: check_suite

      mock_results_get_workflow_steps(
        workflow_run_backend_id: check_run.workflow_job_run.workflow_run_execution.external_id,
        workflow_job_run_backend_id: check_run.external_id,
        steps: [create(:check_step, :results_completed_log_url, name: "First Attempt")]
      )

      check_suite.workflow_run.create_new_workflow_execution(external_id: SimpleUUID::UUID.new.to_guid, attempt: 2)
      new_check_run = create :check_run_for_actions_app, :success, check_suite: check_suite

      mock_results_get_workflow_steps(
        workflow_run_backend_id: new_check_run.workflow_job_run.workflow_run_execution.external_id,
        workflow_job_run_backend_id: new_check_run.external_id,
        steps: [create(:check_step, :results_completed_log_url, name: "Second Attempt")]
      )

      assert_equal check_run.steps_from_results.first.name, "First Attempt"
      assert_equal new_check_run.steps_from_results.first.name, "Second Attempt"
    end

    test "skips results for certain statuses" do
      ActionsResults::Twirp::StepsClient.any_instance.expects(:get_workflow_steps).never

      CheckRun::ActionsDependency::STATUSES_WITHOUT_STEPS.map do |status|
        check_run = create :check_run_for_actions_app, status: status, conclusion: nil
        assert_empty check_run.steps_from_results, "status => #{status}"
      end
    end

    test "skips results for certain conclusions" do
      ActionsResults::Twirp::StepsClient.any_instance.expects(:get_workflow_steps).never

      CheckRun::ActionsDependency::CONCLUSIONS_WITHOUT_STEPS.map do |conclusion|
        check_run = create :check_run_for_actions_app, status: "completed", conclusion: conclusion
        assert_empty check_run.steps_from_results, "conclusion => #{conclusion}"
      end
    end

    test "if workflow job run is cloned it uses original workflow run execution id" do
      check_suite = create :check_suite_for_actions_app, :success
      new_execution = check_suite.workflow_run.create_new_workflow_execution(external_id: SimpleUUID::UUID.new.to_guid, attempt: 2)
      partial_check_run = create :check_run_for_actions_app, :success, check_suite: check_suite, is_cloned_from_previous_run: true
      partial_check_run.workflow_job_run.update!(workflow_run_execution: new_execution)

      mock_results_get_workflow_steps(
        workflow_run_backend_id: partial_check_run.workflow_job_run.original_workflow_run_execution.external_id,
        workflow_job_run_backend_id: partial_check_run.external_id,
        steps: [create(:check_step, :results_completed_log_url, name: "First Attempt")]
      )

      assert_equal partial_check_run.steps_from_results.first.name, "First Attempt"
    end

    test "fallback: returns steps from launch if results service enabled and results fails" do
      GitHub.flipper[:actions_opt_out_results_service].disable

      check_suite = create :check_suite_for_actions_app, :in_progress
      check_run = create :check_run_for_actions_app, :with_steps, :in_progress, check_suite: check_suite
      expected_steps = check_run.steps

      ActionsResults::Twirp::StepsClient
        .any_instance
        .expects(:get_workflow_steps)
        .returns(TwirpResponse.new(
          status: 500,
          call_succeeded: false
        ))
        .once

      mock_steps_for_change_id(repo: check_run.repository, check_run: check_run, change_id: 0)

      assert_equal check_run.steps_from_results.first.name, expected_steps.first.name
    end

    test "fallback: returns steps from RAC if results service enabled and results fails and is not in progress" do
      GitHub.flipper[:actions_opt_out_results_service].disable

      check_suite = create :check_suite_for_actions_app, :success
      check_run = create :check_run_for_actions_app, :with_steps, :success, check_suite: check_suite
      expected_steps = check_run.steps

      ActionsResults::Twirp::StepsClient
        .any_instance
        .expects(:get_workflow_steps)
        .returns(TwirpResponse.new(
          status: 500,
          call_succeeded: false
        ))
        .once

      assert_equal check_run.steps_from_results.first.name, expected_steps.first.name
    end

    test "fallback: returns empty steps results service enabled and fails for an in-progress four nines run" do
      GitHub.flipper[:actions_opt_out_results_service].disable

      check_suite = create :check_suite_for_actions_app, :in_progress
      run_stamp_url = "https://run-stamp.example.com/0"
      check_suite.workflow_run.latest_workflow_run_execution.update!(run_stamp_url: run_stamp_url)
      check_run = create :check_run_for_actions_app, :with_steps, :in_progress, check_suite: check_suite

      ActionsResults::Twirp::StepsClient
      .any_instance
      .expects(:get_workflow_steps)
      .returns(TwirpResponse.new(
        status: 500,
        call_succeeded: false
      ))
      .once

      assert_empty check_run.steps_from_results
    end
  end

  context "#steps_from_backend" do
    test "returns steps from results if results service enabled", skip_enterprise: true do
      GitHub.flipper[:actions_opt_out_results_service].disable

      check_suite = create :check_suite_for_actions_app, :success
      check_run = create :check_run_for_actions_app, :success, check_suite: check_suite

      mock_results_get_workflow_steps(
        workflow_run_backend_id: check_run.workflow_job_run.workflow_run_execution.external_id,
        workflow_job_run_backend_id: check_run.external_id,
        steps: [create(:check_step, :results_completed_log_url, name: "First Attempt")]
      )

      assert_equal check_run.steps_from_backend.first.name, "First Attempt"
    end

    test "returns steps from launch if results service disabled" do
      GitHub.flipper[:actions_opt_out_results_service].enable

      check_suite = create :check_suite_for_actions_app, :success
      check_run = create :check_run_for_actions_app, :with_steps, :success, check_suite: check_suite
      mock_steps_for_change_id(repo: check_run.repository, check_run: check_run, change_id: 0)

      assert_equal check_run.steps_from_backend.first.name, check_run.steps.first.name
    end

    test "skips calling results or launch for a skipped job" do
      ActionsResults::Twirp::StepsClient.any_instance.expects(:get_workflow_steps).never
      Launch::Twirp::ChecksClient.any_instance.expects(:rpc).with(:StepsFromChangeID, anything).never

      CheckRun::ActionsDependency::CONCLUSIONS_WITHOUT_STEPS.map do |conclusion|
        check_run = create :check_run_for_actions_app, status: "completed", conclusion: conclusion
        assert_empty check_run.steps_from_backend, "conclusion => #{conclusion}"
      end
    end
  end

  context "#passthrough_steps?" do
    test "returns false for a completed check run in Enterprise", enterprise_only: true do
      check_run = create(:check_run_for_actions_app, :success)
      refute check_run.passthrough_steps?
    end

    test "returns true for a completed check run when completed steps via results service enabled", skip_enterprise: true do
      GitHub.flipper[:actions_opt_out_results_service].disable
      check_run = create(:check_run_for_actions_app, :success)
      assert check_run.passthrough_steps?
    end

    test "return true for an in progress check run" do
      check_run = create(:check_run_for_actions_app, :in_progress)
      assert check_run.passthrough_steps?
    end

    test "returns true for a 4-nines check run even completed steps via results service disabled" do
      GitHub.flipper[:actions_opt_out_results_service].disable
      check_suite = create :check_suite_for_actions_app, :success
      run_stamp_url = "https://run-stamp.example.com/0"
      check_suite.workflow_run.latest_workflow_run_execution.update!(run_stamp_url: run_stamp_url)
      assert check_suite.workflow_run&.is_actions_four_nines_run?
      check_run = create(:check_run_for_actions_app, :success, check_suite: check_suite)
      assert check_run.passthrough_steps?
    end
  end

  context "#is_actions_check_run?" do
    test "returns false for non actions check run" do
      check_run = create(:check_run)
      refute check_run.is_actions_check_run?
      refute check_run.number.present?
    end

    test "returns true for actions check run" do
      check_run = create(:check_run_for_actions_app)
      assert check_run.is_actions_check_run?
      assert check_run.number.present?
    end
  end

  context "#actions_rerequest" do
    test "delegates to check_suite.rerequest with correct params" do
      check_run = create(:check_run_for_actions_app)
      check_run.check_suite.expects(:rerequest).with(actor: check_run.creator, only_check_run_id: check_run.id, enable_debug_logging: false)
      check_run.actions_rerequest(actor: check_run.creator)
    end

    test "delegates to check_suite.rerequest with enable_debug_logging" do
      check_run = create(:check_run_for_actions_app)
      check_run.check_suite.expects(:rerequest).with(actor: check_run.creator, only_check_run_id: check_run.id, enable_debug_logging: true)
      check_run.actions_rerequest(actor: check_run.creator, enable_debug_logging: true)
    end
  end

  context "#actions_rerequestable?" do
    test "returns false for non actions check run" do
      check_run = create(:check_run)
      refute check_run.actions_rerequestable?
    end

    test "returns true for actions check run" do
      check_run = create(:check_run_for_actions_app)
      assert check_run.actions_rerequestable?
    end

    test "returns false for check run create by launch healer" do
      check_run = create(:check_run_for_actions_app, external_id: "github-actions")
      refute check_run.actions_rerequestable?
    end
  end

  context "#actions_runtime_duration" do
    %w[
      success failure cancelled
    ].each do |conclusion|
      test "`returns normal duration for runs that have a positive duration with a conclusion of #{conclusion}`" do
        check_run = create(:check_run_for_actions_app, started_at: 2.hours.ago, completed_at: 1.hour.ago, conclusion: conclusion, status: "completed")
        assert_equal check_run.duration, check_run.actions_runtime_duration
      end
    end

    %w[
      success failure cancelled
    ].each do |conclusion|
      test "`returns 1 for completed runs that have a negative duration with a conclusion of #{conclusion}`" do
        check_run = create(:check_run_for_actions_app, started_at: 2.seconds.ago, completed_at: 3.seconds.ago, conclusion: conclusion, status: "completed")
        assert_equal 1, check_run.actions_runtime_duration
      end
    end

    test "returns check run duration for runs wth a conclusion of skipped regardless of duration" do
      check_run_zero = create(:check_run_for_actions_app, started_at: 2.seconds.ago, completed_at: 2.seconds.ago, conclusion: "skipped", status: "completed")
      assert_equal check_run_zero.duration, check_run_zero.actions_runtime_duration

      check_run_positive = create(:check_run_for_actions_app, started_at: 2.hours.ago, completed_at: 1.hour.ago, conclusion: "skipped", status: "completed")
      assert_equal check_run_positive.duration, check_run_positive.actions_runtime_duration

      # no reported instances of skipped jobs with negative durations so no need to test
    end
  end

  context "#reusable_workflow_display_names" do
    test "returns nil if no display_name" do
      check_run = create(:check_run_for_actions_app, display_name: nil)
      assert_nil check_run.reusable_workflow_display_names
    end

    test "returns nil if there is no / in the display_name" do
      check_run = create(:check_run_for_actions_app, display_name: "Just a normal job")
      assert_nil check_run.reusable_workflow_display_names
    end

    test "correctly returns names if single child" do
      check_run = create(:check_run_for_actions_app, display_name: "Parent / Child A")
      parent_name, child_name = check_run.reusable_workflow_display_names
      assert_equal "Parent", parent_name
      assert_equal "Child A", child_name
    end

    test "correctly returns names if two children" do
      check_run = create(:check_run_for_actions_app, display_name: "Parent / Child A / Child B")
      parent_name, child_name = check_run.reusable_workflow_display_names
      assert_equal "Parent", parent_name
      assert_equal "Child B", child_name
    end

    test "correctly returns names if more than two children" do
      check_run = create(:check_run_for_actions_app, display_name: "Parent / Child A / Child B / Child C")
      parent_name, child_name = check_run.reusable_workflow_display_names
      assert_equal "Parent", parent_name
      assert_equal "Child C", child_name
    end

    test "does not split names with no spaces" do
      check_run = create(:check_run_for_actions_app, display_name: "Parent / Test my_org/my_repo")
      parent_name, child_name = check_run.reusable_workflow_display_names
      assert_equal "Parent", parent_name
      assert_equal "Test my_org/my_repo", child_name
    end
  end

  context "stafftools force cancel" do
    test "not available for non-actions check runs" do
      check_run = create(:check_run, status: "completed", conclusion: "success", completed_at: 2.days.ago, updated_at: 2.days.ago)
      refute check_run.force_cancel_eligible_from_stafftools?
    end

    test "not availible for completed runs" do
      check_run = create(:check_run_for_actions_app, status: "completed", conclusion: "success", completed_at: 2.days.ago, updated_at: 2.days.ago)
      refute check_run.force_cancel_eligible_from_stafftools?
    end

    test "not available for runs updated in the last 6 hours" do
      check_run = create(:check_run_for_actions_app, status: "in_progress", updated_at: 5.hours.ago)
      refute check_run.force_cancel_eligible_from_stafftools?
    end

    test "available for in-progress runs older than 6 hours" do
      check_run = create(:check_run_for_actions_app, status: "in_progress", updated_at: 7.hours.ago)
      assert check_run.force_cancel_eligible_from_stafftools?
    end
  end

  context "opt out of results" do
    test "returns true if actions_opt_out_results_service feature flag is enabled for repo", skip_enterprise: true do
      check_run = create(:check_run_for_actions_app, check_suite: @check_suite, status: "in_progress", updated_at: 25.hours.ago)
      GitHub.flipper[:actions_opt_out_results_service].enable(@repo)
      GitHub.flipper[:actions_opt_out_results_service].disable(@org)
      assert check_run.opt_out_from_results?
    end
    test "returns true if actions_opt_out_results_service feature flag is enabled for org", skip_enterprise: true do
      check_run = create(:check_run_for_actions_app, check_suite: @check_suite, status: "in_progress", updated_at: 25.hours.ago)
      GitHub.flipper[:actions_opt_out_results_service].enable(@org)
      GitHub.flipper[:actions_opt_out_results_service].disable(@repo)
      assert check_run.opt_out_from_results?
    end
    test "returns false for completed_steps_via_results_service if opt_out_from_results returns true", skip_enterprise: true do
      check_run = create(:check_run_for_actions_app, check_suite: @check_suite, status: "in_progress", updated_at: 25.hours.ago)
      GitHub.flipper[:actions_opt_out_results_service].enable(@org)
      refute check_run.completed_steps_via_results_service?
    end
    test "returns false for streaming_logs_via_results if opt_out_from_results returns true", skip_enterprise: true do
      check_run = create(:check_run_for_actions_app, check_suite: @check_suite, status: "in_progress", updated_at: 25.hours.ago)
      GitHub.flipper[:actions_opt_out_results_service].enable(@org)
      refute check_run.streaming_logs_via_results?
    end
    test "returns false for steps_via_results_service if opt_out_from_results returns true", skip_enterprise: true do
      check_run = create(:check_run_for_actions_app, check_suite: @check_suite, status: "in_progress", updated_at: 25.hours.ago)
      GitHub.flipper[:actions_opt_out_results_service].enable(@org)
      refute check_run.streaming_logs_via_results?
    end
    test "returns true for streaming_logs_via_results if opt_out_from_results false", skip_enterprise: true do
      check_run = create(:check_run_for_actions_app, check_suite: @check_suite, status: "in_progress", updated_at: 25.hours.ago)
      GitHub.flipper[:actions_opt_out_results_service].disable(@org)
      assert check_run.streaming_logs_via_results?
    end
    test "returns true for completed_steps_via_results_service if opt_out_from_results returns false but is from 2023", skip_enterprise: true do
      check_run = create(:check_run_for_actions_app, check_suite: @check_suite, status: "in_progress", updated_at: 25.hours.ago, started_at: Time.zone.parse("2023-12-29 00:00:00"))
      GitHub.flipper[:actions_opt_out_results_service].enable(@org)
      refute check_run.completed_steps_via_results_service?
    end
    test "returns true for completed_steps_via_results_service if opt_out_from_results returns false but is from 2024", skip_enterprise: true do
      check_run = create(:check_run_for_actions_app, check_suite: @check_suite, status: "in_progress", updated_at: 25.hours.ago, started_at: Time.zone.parse("2024-01-01 00:00:00"))
      GitHub.flipper[:actions_opt_out_results_service].disable(@org)
      assert check_run.completed_steps_via_results_service?
    end
    test "returns true for completed_steps_via_results_service if opt_out_from_results returns false but is from 2025", skip_enterprise: true do
      check_run = create(:check_run_for_actions_app, check_suite: @check_suite, status: "in_progress", updated_at: 25.hours.ago, started_at: Time.zone.parse("2025-01-01 00:00:00"))
      GitHub.flipper[:actions_opt_out_results_service].disable(@org)
      assert check_run.completed_steps_via_results_service?
    end

    test "returns true for opt_out_from_results on enterprise", enterprise_only: true do
      check_run = create(:check_run_for_actions_app, check_suite: @check_suite, status: "in_progress", updated_at: 25.hours.ago)
      GitHub.flipper[:actions_opt_out_results_service].disable(@org)
      assert_predicate check_run, :opt_out_from_results?
    end
  end

  context "disable dotcom check steps writes" do
    test "returns true if actions_disable_dotcom_check_steps_writes enabled for dotcom", skip_enterprise: true do
      check_run = create(:check_run_for_actions_app, check_suite: @check_suite, status: "in_progress", updated_at: 25.hours.ago)
      GitHub.flipper[:actions_opt_out_results_service].disable(@repo)
      assert check_run.disable_dotcom_check_steps_writes?
    end
    test "returns false if opt_out_from_results returns true for dotcom", skip_enterprise: true do
      check_run = create(:check_run_for_actions_app, check_suite: @check_suite, status: "in_progress", updated_at: 25.hours.ago)
      GitHub.flipper[:actions_opt_out_results_service].enable(@org)
      refute check_run.disable_dotcom_check_steps_writes?
    end
    test "returns false if running in enterprise", enterprise_only: true do
      check_run = create(:check_run_for_actions_app, check_suite: @check_suite, status: "in_progress", updated_at: 25.hours.ago)
      GitHub.flipper[:actions_opt_out_results_service].disable(@org)
      refute check_run.disable_dotcom_check_steps_writes?
    end
  end

  context "#system_logs_from_results?" do
    test "false if completed" do
      check_run = create(:check_run_for_actions_app, :four_nines, status: :completed, conclusion: :success)
      refute check_run.system_logs_from_results?
    end

    test "false if not four nines" do
      check_run = create(:check_run_for_actions_app, status: :in_progress)
      refute check_run.system_logs_from_results?
    end

    test "true if four nines and in progress" do
      check_run = create(:check_run_for_actions_app, :four_nines, status: :in_progress)
      assert check_run.system_logs_from_results?
    end
  end

  context "#system_logs" do
    test "nil if not four nines" do
      check_run = create(:check_run_for_actions_app, status: :in_progress)
      assert_nil check_run.system_logs
    end

    test "nil on request failure" do
      check_run = create(:check_run_for_actions_app, :four_nines, status: :in_progress)

      ActionsResults::Twirp::LogClient
        .any_instance
        .expects(:get_step_log_scrollback)
        .with(equals({
          workflow_run_backend_id: check_run.check_suite.external_id,
          workflow_job_run_backend_id: check_run.external_id,
          workflow_step_backend_id: ActionsResults::Utils::SYSTEM_LOGS_KEY,
        }))
        .returns(TwirpResponse.new(
          status: 500,
          call_succeeded: false,
        ))

      assert_nil check_run.system_logs
    end

    test "returns system logs for four nines run" do
      check_run = create(:check_run_for_actions_app, :four_nines, status: :in_progress)

      ActionsResults::Twirp::LogClient
        .any_instance
        .expects(:get_step_log_scrollback)
        .with(equals({
          workflow_run_backend_id: check_run.check_suite.external_id,
          workflow_job_run_backend_id: check_run.external_id,
          workflow_step_backend_id: ActionsResults::Utils::SYSTEM_LOGS_KEY,
        }))
        .returns(TwirpResponse.new(
          status: 200,
          call_succeeded: true,
          value: MonolithTwirp::ActionsResults::Core::V1::GetStepLogScrollbackResponse.new(
            lines: [
              MonolithTwirp::ActionsResults::Core::V1::GetStepLogScrollbackResponse::LogLine.new(
                line: "hello"
              ),
              MonolithTwirp::ActionsResults::Core::V1::GetStepLogScrollbackResponse::LogLine.new(
                line: "world"
              )
            ]
          )
        ))

      assert_equal check_run.system_logs, "hello\nworld"
    end
  end
end
