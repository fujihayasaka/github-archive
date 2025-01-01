# typed: true
# frozen_string_literal: true

require "test_helper"

class Checks::WorkflowUpdateTest < GitHub::TestCase
  fixtures do
    @user = create(:user, plan: "pro")
    @repo = create(:repository, name: "hello-world", owner: @user)

    @check_suite = create(
      :check_suite,
      repository: @repo
    )

    @check_run = create(
      :check_run,
      :with_steps,
      check_suite: @check_suite,
      repository: @repo
    )

    environment = create(:environment, repository: @repo)
    @gate_obj = create(:gate, environment: environment)
  end

  setup do
    GitHub.stubs(:actions_enabled?).returns(true)

    @check_run_number = 3
    @runner_id = 2
    @runner_name = "ip-172-19-32-146"
    @job_key = "build.__default"
    @runner_group_id = 1
    @runner_group_name = "Default"
    @parent_job_id = "build"
    @check_run_external_id = "ca395085-040a-526b-2ce8-bdc85f692774"
    @annotation_message = "This is an annotation one"
    @annotation_end_column = 1
    @annotation_end_line = 3
    @annotation_file_path = "app/models/checks/workflow_update.rb"
    @annotation_raw_details = "{ key: value }"
    @annotation_start_column = 78
    @annotation_start_line = 426
    @annotation_title = "title for an annotation"
    @annotation_step_number = 3
    @gate_token = "gate_token"
    @gate_state = :STATE_OPEN
    @gate_concluded = false
    @artifact_name = "artifact name"
    @artifact_size = 100
    @artifact_url = "http://example.com/artifact"
    @completed_log_url = "http://example.com/completed_log"
    @completed_log_lines = 598
    @check_run_display_name = "build"
    @check_run_labels = %w[label1 label2]
    @step_name = "step name"
    @step_number = 1
    @step_external_id = "step_external_id"
    @summary_url = "http://example.com/summary"
    @step_completed_log_url = "http://example.com/step_completed_log"
    @step_completed_log_lines = 598
    @is_cloned_from_previous_run = false

    @concurrency = {
      group: "concurrency group",
      waiting_on_resource: {
        check_run_global_id: @check_run.global_relay_id,
        check_suite_global_id: @check_suite.global_relay_id
      }
    }
    @protobuf_time = {
      seconds: Time.now.to_i,
      nanos: 466666700
    }
    @matched_time = Google::Protobuf::Timestamp.new(@protobuf_time).to_time

    @check_run_step_in_progress = {
      started_at: @protobuf_time,
      status: :STATUS_IN_PROGRESS,
    }
    @check_run_step_complete = {
      result: :RESULT_FAILED,
      started_at: @protobuf_time,
      completed_at: @protobuf_time,
      log: {
        lines: @completed_log_lines,
        url: @completed_log_url,
        created_at: @protobuf_time
      }
    }

    @steps = [
      {
        external_id: @step_external_id,
        number: @step_number,
        name: @step_name,
        in_progress: nil,
        complete: {
          started_at: @protobuf_time,
          completed_at: @protobuf_time,
          result: :RESULT_SUCCEEDED,
          log: {
            url: @step_completed_log_url,
            lines: @step_completed_log_lines,
            created_at: @protobuf_time
          }
      },
        queued: nil
      }
    ]

    @artifact = {
      name: @artifact_name,
      size: @artifact_size,
      url: @artifact_url,
      created_at: @protobuf_time,
      expires_at: @protobuf_time
    }

    @annotations = [
      {
        annotation_level: :LEVEL_WARNING,
        message: @annotation_message,
        raw_details: @annotation_raw_details,
        file_path: @annotation_file_path,
        start_line: @annotation_start_line,
        end_line: @annotation_end_line,
        start_column: @annotation_start_column,
        end_column: @annotation_end_column,
        step_number: @annotation_step_number,
        title: @annotation_title
      }
    ]

    @run = {
      status: :STATUS_PENDING,
      conclusion: :CONCLUSION_SUCCEEDED,
      started_at: @protobuf_time,
      completed_at: @protobuf_time,
      completed_log: {
        url: @completed_log_url,
        lines: @completed_log_lines,
        created_at: @protobuf_time,
      },
      concurrency: @concurrency,
      artifacts: [@artifact],
      annotations: @annotations,
      check_suite_id: @check_suite.global_relay_id,
    }

    @gate = {
      gate_id: @gate_obj.global_relay_id,
      check_run_id: @check_run.global_relay_id,
      token: @gate_token,
      state: @gate_state,
      concluded: @gate_concluded,
      expires_at: @protobuf_time
    }

    @streaming_log = {
      url: "http://example.com/log_stream",
      # these are unused :)
      token: "log_stream_token",
      expires_at: @protobuf_time
    }

    @completed_log = {
      url: @completed_log_url,
      lines: @completed_log_lines,
      created_at: @protobuf_time
    }

    @job_complete = {
      started_at: @protobuf_time,
      completed_at: @protobuf_time,
      result: :RESULT_FAILED,
      log: @completed_log,
      summary: {
        url: @summary_url,
      }
    }

    @job_in_progress = {
      started_at: @protobuf_time,
      status: :STATUS_IN_PROGRESS,
      log_stream: {
        url: "http://example.com/log_stream",
        token: "log_stream_token",
        expires_at: @protobuf_time,
      },
      log: {
        lines: 529,
        url: "http://example.com/log",
        created_at: @protobuf_time,
      }
    }

    @job = {
      check_run_id: @check_run.global_relay_id,
      job_id: "job_id",
      external_id: @check_run_external_id,
      number: @check_run_number,
      display_name: @check_run_display_name,
      artifacts: [@artifact],
      steps: @steps,
      in_progress: nil, # @job_in_progress,
      # log_stream: deprecated
      complete: @job_complete, # @job_complete,
      annotations: @annotations,
      job_key: @job_key,
      runtime: "ubuntu",
      runtime_version: "7.0.1",
      self_hosted: true,
      duration_ms: 333517,
      delayed: false,
      environment: {
        name: "environment name",
        url: "http://example.com"
      },
      parent_job_id: @parent_job_id,
      labels: @check_run_labels,
      runner_id: @runner_id,
      runner_name: @runner_name,
      runner_group_id: @runner_group_id,
      runner_group_name: @runner_group_name,
      concurrency: @concurrency,
      is_cloned_from_previous_run: @is_cloned_from_previous_run,
    }

    @update_check_run_message = {
      repository_id: @repo.global_relay_id,
      workflow_run_id: "242b4779-bd76-4211-ba2d-f568d2f3c6db",
      job: @job,
      run: nil,
      gate: nil,
    }

    @update_check_suite_message = {
      repository_id: @repo.global_relay_id,
      workflow_run_id: "242b4779-bd76-4211-ba2d-f568d2f3c6db",
      run: @run,
      job: nil,
      gate: nil,
    }

    @update_gate_request_message = {
      repository_id: @repo.global_relay_id,
      workflow_run_id: "242b4779-bd76-4211-ba2d-f568d2f3c6db",
      gate: @gate,
      run: nil,
      job: nil,
    }

    @update_check_run = Checks::WorkflowUpdate.new(@update_check_run_message)
    @update_check_suite = Checks::WorkflowUpdate.new(@update_check_suite_message)
    @update_gate_request = Checks::WorkflowUpdate.new(@update_gate_request_message)
  end

  context "#update_type" do
    test "returns :job for a job update" do
      assert_equal :job, @update_check_run.update_type
    end

    test "returns :run for a run update" do
      assert_equal :run, @update_check_suite.update_type
    end

    test "returns :gate for a gate update" do
      assert_equal :gate, @update_gate_request.update_type
    end
  end

  context "#check_run_id" do
    test "returns the check run id for a job update" do
      check_run_id = @update_check_run.check_run_id

      assert_equal @check_run.id, check_run_id
    end

    test "returns the check run id for a gate update" do
      check_run_id = @update_gate_request.check_run_id

      assert_equal @check_run.id, check_run_id
    end

    test "returns nil for a run update" do
      check_run_id = @update_check_suite.check_run_id

      assert_nil check_run_id
    end
  end

  context "#check_suite_id" do
    test "returns the check suite id for a run update" do
      check_suite_id = @update_check_suite.check_suite_id

      assert_equal @check_suite.id, check_suite_id
    end

    test "returns nil for a gate update" do
      check_suite_id = @update_gate_request.check_suite_id

      assert_nil check_suite_id
    end

    test "returns nil for a job update" do
      check_suite_id = @update_check_run.check_suite_id

      assert_nil check_suite_id
    end
  end

  context "#check_run_update_data" do
    test "returns annotations" do
      result = @update_check_run.check_run_update_data

      assert_equal [{
        repository_id: @repo.id,
        warning_level: "warning",
        message: @annotation_message,
        raw_details: @annotation_raw_details,
        filename: @annotation_file_path,
        start_line: @annotation_start_line,
        end_line: @annotation_end_line,
        start_column: @annotation_start_column,
        end_column: @annotation_end_column,
        step_number: @annotation_step_number,
        title: @annotation_title,
      }], result[:annotations]
    end

    test "returns nil concurrency when concurrency isn't available" do
      @job[:concurrency] = nil

      result = @update_check_run.check_run_update_data

      assert_nil result[:concurrency]
    end

    test "returns concurrency when waiting on resource isn't available" do
      @job[:concurrency] = {
        group: "concurrency group",
      }
      result = @update_check_run.check_run_update_data

      assert_equal ({
        group: "concurrency group"
      }), result[:concurrency]
    end

    test "returns concurrency when waiting on resource is empty" do
      @job[:concurrency] = {
        group: "concurrency group",
        waiting_on_resource: {}
      }

      result = @update_check_run.check_run_update_data

      assert_equal ({
        waiting_on_resource: {},
        group: "concurrency group"
      }), result[:concurrency]
    end

    test "returns concurrency when global IDs are nil" do
      @job[:concurrency] = {
        group: "concurrency group",
        waiting_on_resource: {
          check_run_global_id: nil,
          check_suite_global_id: nil,
        }
      }
      result = @update_check_run.check_run_update_data

      assert_equal ({
        waiting_on_resource: {
          check_run_global_id: nil,
          check_suite_global_id: nil,
        },
        group: "concurrency group"
      }), result[:concurrency]
    end

    test "returns concurrency when no ids are present" do
      @job[:concurrency] = {
        group: "concurrency group",
        waiting_on_resource: {
          check_run_global_id: "",
          check_suite_global_id: "",
        }
      }
      result = @update_check_run.check_run_update_data

      assert_equal ({
        waiting_on_resource: {
          check_run_global_id: "",
          check_suite_global_id: "",
        },
        group: "concurrency group"
      }), result[:concurrency]
    end

    test "returns concurrency" do
      result = @update_check_run.check_run_update_data

      assert_equal ({
        waiting_on_resource: {
          check_run_global_id: @check_run.global_relay_id,
          check_suite_global_id: @check_suite.global_relay_id,
          check_run_id: @check_run.id.to_i,
          check_suite_id: @check_suite.id.to_i,
        },
        group: "concurrency group"
      }), result[:concurrency]
    end

    test "returns is_cloned_from_previous_run" do
      result = @update_check_run.check_run_update_data

      assert_equal @is_cloned_from_previous_run, result[:is_cloned_from_previous_run]
    end

    context "return check run updates" do
      test "returns all values for in progress" do
        in_progress_message = @update_check_run_message
        in_progress_message[:job][:in_progress] = @job_in_progress
        in_progress_message[:job][:complete] = nil

        new_update_check_run = Checks::WorkflowUpdate.new(in_progress_message)
        result = new_update_check_run.check_run_update_data

        assert_equal ({
          external_id: @check_run_external_id,
          display_name: @check_run_display_name,
          status: CheckRun.statuses[:in_progress],
          number: @check_run_number,
          started_at: @matched_time,
          streaming_log_url: @streaming_log[:url],
        }), result[:check_run_updates]
      end

      test "does not return streaming log url for in progress when no log stream is present" do
        @job_in_progress.delete(:log_stream)

        in_progress_message = @update_check_run_message
        in_progress_message[:job][:in_progress] = @job_in_progress
        in_progress_message[:job][:complete] = nil

        new_update_check_run = Checks::WorkflowUpdate.new(in_progress_message)
        result = new_update_check_run.check_run_update_data

        assert_equal false, result[:check_run_updates].key?(:streaming_log_url)
      end

      test "returns all values for complete" do
        result = @update_check_run.check_run_update_data

        assert_equal ({
          external_id: @check_run_external_id,
          display_name: @check_run_display_name,
          status: CheckRun.statuses[:completed],
          number: @check_run_number,
          conclusion: CheckRun.conclusions[:failure],
          completed_at: @matched_time,
          started_at: @matched_time,
          completed_log_url: @completed_log[:url],
          completed_log_lines: @completed_log[:lines],
        }), result[:check_run_updates]
      end

      test "does not return completed log data if check run was cloned" do
        @job[:is_cloned_from_previous_run] = true

        result = @update_check_run.check_run_update_data

        assert_equal ({
          external_id: @check_run_external_id,
          display_name: @check_run_display_name,
          status: CheckRun.statuses[:completed],
          number: @check_run_number,
          conclusion: CheckRun.conclusions[:failure],
          completed_at: @matched_time,
          started_at: @matched_time,
        }), result[:check_run_updates]
      end

      test "does not return completed log data if no complete log is available" do
        @job_complete.delete(:log)

        result = @update_check_run.check_run_update_data

        assert_equal ({
          external_id: @check_run_external_id,
          display_name: @check_run_display_name,
          status: CheckRun.statuses[:completed],
          number: @check_run_number,
          conclusion: CheckRun.conclusions[:failure],
          completed_at: @matched_time,
          started_at: @matched_time,
        }), result[:check_run_updates]
      end
    end

    test "return check run steps" do
      result = @update_check_run.check_run_update_data

      assert_equal [{
        number: @step_number,
        external_id: @step_external_id,
        name: @step_name,
        conclusion: CheckRun.conclusions[:success],
        status: CheckStep.statuses[:completed],
        completed_at: @matched_time,
        started_at: @matched_time,
        completed_log: {
          url: @step_completed_log_url,
          lines: @step_completed_log_lines,
        },
      }], result[:check_run_steps]
    end

    test "return check run steps without completed_log when none is present" do
      step_complete = @update_check_run_message.dig(:job, :steps, 0, :complete)
      step_complete.delete(:log)

      update_check_run = Checks::WorkflowUpdate.new(@update_check_run_message)

      result = update_check_run.check_run_update_data

      assert_equal [{
        number: @step_number,
        external_id: @step_external_id,
        name: @step_name,
        conclusion: CheckRun.conclusions[:success],
        status: CheckStep.statuses[:completed],
        completed_at: @matched_time,
        started_at: @matched_time,
      }], result[:check_run_steps]
    end

    test "return workflow job run data" do
      result = @update_check_run.check_run_update_data

      assert_equal ({
        job_key: @job_key,
        parent_job_id: @parent_job_id,
        runner_id: @runner_id,
        runner_name: @runner_name,
        runner_group_id: @runner_group_id,
        runner_group_name: @runner_group_name,
        label_data: @check_run_labels,
        summary_url: @summary_url,
      }), result[:workflow_job_run]
    end

    context "when annotations have 0 in line numbers" do
      test "should set lines to nil" do
        new_check_run_message = @update_check_run_message
        new_check_run_message[:job][:annotations] = [
          {
            annotation_level: :LEVEL_WARNING,
            message: @annotation_message,
            raw_details: @annotation_raw_details,
            file_path: @annotation_file_path,
            start_line: 0,
            end_line: 0,
            start_column: @annotation_start_column,
            end_column: @annotation_end_column,
            step_number: @annotation_step_number,
            title: @annotation_title
          }
        ]

        new_update_check_run = Checks::WorkflowUpdate.new(new_check_run_message)
        result = new_update_check_run.check_run_update_data

        assert_equal [{
          repository_id: @repo.id,
          warning_level: "warning",
          message: @annotation_message,
          raw_details: @annotation_raw_details,
          filename: @annotation_file_path,
          start_column: @annotation_start_column,
          end_column: @annotation_end_column,
          step_number: @annotation_step_number,
          title: @annotation_title,
        }], result[:annotations]
      end
    end
  end

  context "#check_suite_update_data" do
    test "returns annotations" do
      result = @update_check_suite.check_suite_update_data

      assert_equal [{
        repository_id: @repo.id,
        warning_level: "warning",
        message: @annotation_message,
        raw_details: @annotation_raw_details,
        filename: @annotation_file_path,
        start_line: @annotation_start_line,
        end_line: @annotation_end_line,
        start_column: @annotation_start_column,
        end_column: @annotation_end_column,
        step_number: @annotation_step_number,
        title: @annotation_title,
      }], result[:annotations]
    end

    test "returns artifacts" do
      result = @update_check_suite.check_suite_update_data

      assert_equal [{
        name: @artifact[:name],
        source_url: @artifact[:url],
        size: @artifact[:size],
        repository_id: @repo.id,
        created_at: @matched_time,
        expires_at: @matched_time,
      }], result[:artifacts]
    end

    test "returns concurrency" do
      result = @update_check_suite.check_suite_update_data

      assert_equal ({
        waiting_on_resource: {
          check_run_global_id: @check_run.global_relay_id,
          check_suite_global_id: @check_suite.global_relay_id,
          check_run_id: @check_run.id.to_i,
          check_suite_id: @check_suite.id.to_i
        },
        group: "concurrency group"
      }), result[:concurrency]
    end

    test "all conclusions have a mapping" do
      Hydro::Schemas::Github::Actions::V0::WorkflowUpdate::RunUpdate::RunConclusion.constants.each do |conclusion|
        run = @run.dup
        run[:conclusion] = conclusion

        update = Checks::WorkflowUpdate.new({
          repository_id: @repo.global_relay_id,
          workflow_run_id: SecureRandom.uuid,
          run: run,
          job: nil,
          gate: nil,
        })

        if conclusion == :CONCLUSION_UNKNOWN
          assert_nil update.check_suite_update_data[:conclusion]
        else
          refute_nil update.check_suite_update_data[:conclusion]
          assert_equal Checks::WorkflowUpdate::CHECK_SUITE_CONCLUSION_MAP[conclusion], update.check_suite_update_data[:conclusion]
        end
      end
    end

    test "returns conclusion" do
      result = @update_check_suite.check_suite_update_data

      assert_equal CheckSuite.conclusions[:success], result[:conclusion]
    end

    test "returns check suite updates" do
      result = @update_check_suite.check_suite_update_data

      assert_equal ({
        completed_log_url: @completed_log_url,
        status: CheckSuite.statuses[:pending],
      }), result[:check_suite_updates]
    end
  end

  context "#gate_request_update_data" do
    test "returns gate request updates" do
      result = @update_gate_request.gate_request_update_data

      assert_equal ({
        gate_id: @gate_obj.id,
        check_run_id: @check_run.id,
        gate_state: "open",
        concluded: @gate_concluded,
        expires_at: @matched_time,
        token: @gate_token,
      }), result
    end
  end
end
