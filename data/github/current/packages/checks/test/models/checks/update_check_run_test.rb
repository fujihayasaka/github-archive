# typed: true
# frozen_string_literal: true

require "test_helper"

class Checks::UpdateCheckRunTest < GitHub::TestCase
  setup do
    GitHub.stubs(:actions_enabled?).returns(true)
  end

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @user = create(:user, plan: "pro")
    @repo = create(:repository, name: "hello-world", owner: @user, from_example: :rebase_pull_request)


    commit = @repo.heads.find("contrib").append_commit({ message: "blah", committer: @user }, @user) do |files|
      files.add("foo", "dsfdsfsdfsd")
    end
    @sha = commit.oid

    make_trusted_oauth_apps_owner

    @check_suite = create(
      :check_suite_for_actions_app,
      repository: @repo,
      head_sha: @sha,
      explicit_completion: true,
      head_branch: nil
    )

    @check_run = create(
      :check_run_for_actions_app,
      :with_steps,
      check_suite: @check_suite,
      status: "queued",
      name: "coverage-test",
      display_name: "Coverage"
    )

    @github_app = create(
      :integration,
      default_permissions: { "checks" => :write, "metadata" => :read },
      name: "Super-Duper",
      owner: @user,
      url: "http://super-duper.com"
    )
  end

  setup do
    @deployment_environment = {
      name: "example_env",
      url: nil
    }

    second_check_step = @check_run.steps.find_by(number: 1)
    @updated_check_step_name = "updated name"
    @updated_check_step_status = CheckStep.statuses[:queued]
    @updated_check_step_external_id = "external-new-stuff"
    @updated_check_step_complete_log_url = "https://example.com/log"
    @updated_check_step_complete_log_lines = 10

    @second_check_step_updates = {
      number: second_check_step.number,
      external_id: @updated_check_step_external_id,
      name: @updated_check_step_name,
      status: @updated_check_step_status,
      completed_log: {
        url: @updated_check_step_complete_log_url,
        lines: @updated_check_step_complete_log_lines,
      },
      conclusion: CheckStep.conclusions[:success],
    }

    @new_step_number = @check_run.steps.sort_by(&:number).last.number + 1

    @new_step_data = {
      number: @new_step_number,
      status: CheckStep.statuses[:queued],
      external_id: "1234",
      name: "new step",
      conclusion: CheckStep.conclusions[:neutral],
    }
    @steps = [@second_check_step_updates, @new_step_data]

    @updated_display_name = "New Display Name"
    @updated_external_id = "5678"
    @updated_check_run_number = "9"
    @completed_log_url = "http://example.com/completed_log"
    @completed_log_lines = 598
    @streaming_log_url = "http://example.com/streaming_log"
    @runner_id = 2
    @runner_name = "ip-172-19-32-146"
    @job_key = "build.__default"
    @runner_group_id = 1
    @runner_group_name = "Default"
    @parent_job_id = "build"
    @annotation_message = "This is an annotation one"
    @annotation_start_column = 15
    @annotation_end_column = 15
    @annotation_start_line = 10
    @annotation_end_line = 10
    @annotation_file_path = "app/models/checks/workflow_update.rb"
    @annotation_raw_details = "{ key: value }"
    @annotation_title = "title for an annotation"
    @labels = %w[label1 label2]
    @time = DateTime.current
    @updated_conclusion = CheckRun.conclusions[:failure]
    @concurrency_check_run_id = "fake_id"
    @updated_check_run_status = CheckRun.statuses[:completed]
    @is_cloned_from_previous_run = false
    @annotations = [
      {
        warning_level: "warning",
        message: @annotation_message,
        raw_details: @annotation_raw_details,
        filename: @annotation_file_path,
        start_line: @annotation_start_line,
        end_line: @annotation_end_line,
        start_column: @annotation_start_column,
        end_column: @annotation_end_column,
        title: @annotation_title,
        repository_id: @repo.id,
      }
    ]
    @invalid_annotation = {
      warning_level: "warning",
      message: @annotation_message,
      raw_details: @annotation_raw_details,
      filename: @annotation_file_path,
      # This is invalid because start_line is greater than end_line
      start_line: 15,
      end_line: 10,
      start_column: @annotation_start_column,
      end_column: @annotation_end_column,
      title: @annotation_title,
      repository_id: @repo.id,
    }
    @check_run_updates = {
      annotations: @annotations,
      concurrency: {
        waiting_on_resource: {
          check_run_id: @concurrency_check_run_id,
        }
      },
      check_run_updates: {
        external_id: @updated_external_id,
        display_name: @updated_display_name,
        status: @updated_check_run_status,
        number: @updated_check_run_number,
        conclusion: @updated_conclusion,
        completed_at: @time,
        started_at: @time,
        completed_log_url: @completed_log_url,
        completed_log_lines: @completed_log_lines,
        streaming_log_url: @streaming_log_url,
      },
      deployment_environments: nil,
      check_run_steps: @steps,
      is_cloned_from_previous_run: @is_cloned_from_previous_run,
      workflow_job_run: {
        job_key: @job_key,
        parent_job_id: @parent_job_id,
        runner_id: @runner_id,
        runner_name: @runner_name,
        runner_group_id: @runner_group_id,
        runner_group_name: @runner_group_name,
        label_data: @labels,
      },
    }
  end

  def subject
    Checks::UpdateCheckRun.new(
      check_run: @check_run,
      update_properties: @check_run_updates,
    )
  end

  def deep_clone(obj)
    Marshal.load(Marshal.dump(obj))
  end

  context ".call" do
    context "when updating a check run" do
      test "check run should have deployment without url set" do
        new_updates = deep_clone(@check_run_updates)
        new_updates[:deployment_environments] = @deployment_environment

        Checks::UpdateCheckRun.call(
          check_run: @check_run,
          update_properties: new_updates,
        )

        @check_run.reload

        refute_nil @check_run.deployment
        assert_equal @deployment_environment[:name], @check_run.deployment.environment
        assert_nil @check_run.deployment.latest_status.environment_url

      end

      test "check run should have deployment" do
        new_updates = deep_clone(@check_run_updates)
        new_environment = deep_clone(@deployment_environment)
        new_environment[:url] = "https://tiny.coffee"
        new_updates[:deployment_environments] = new_environment

        Checks::UpdateCheckRun.call(
          check_run: @check_run,
          update_properties: new_updates,
        )

        @check_run.reload

        refute_nil @check_run.deployment
        assert_equal new_environment[:name], @check_run.deployment.environment
        assert_equal new_environment[:url], @check_run.deployment.latest_status.environment_url

      end

      test "cloned check run should not have deployment" do
        new_updates = deep_clone(@check_run_updates)
        new_updates[:is_cloned_from_previous_run] = true
        new_environment = deep_clone(@deployment_environment)
        new_environment[:url] = "https://tiny.coffee"
        new_updates[:deployment_environments] = new_environment

        Checks::UpdateCheckRun.call(
          check_run: @check_run,
          update_properties: new_updates,
        )

        @check_run.reload

        assert_nil @check_run.deployment
      end

      test "should assign the new check run the correct attributes" do
        subject.call

        @check_run.reload

        assert_equal @updated_display_name, @check_run.display_name
        assert_equal @updated_external_id, @check_run.external_id
        assert_equal "completed", @check_run.status
        assert_equal "failure", @check_run.conclusion
        assert_equal @updated_check_run_number.to_i, @check_run.number.to_i
        assert_equal @time.to_i, @check_run.completed_at.to_i
        assert_equal @time.to_i, @check_run.started_at.to_i
        assert_equal @completed_log_url, @check_run.completed_log_url
        assert_equal @completed_log_lines, @check_run.completed_log_lines
        assert_equal @streaming_log_url, @check_run.streaming_log_url
      end

      test "should not overwrite existing values with nil if they are not present in the update" do
        new_updates = deep_clone(@check_run_updates)
        new_updates[:check_run_updates][:number] = nil
        new_updates[:check_run_updates][:display_name] = nil
        @check_run.update!(number: 7)

        Checks::UpdateCheckRun.call(
          check_run: @check_run,
          update_properties: new_updates,
        )

        @check_run.reload

        refute_nil @check_run.number
        refute_nil @check_run.display_name
      end

      test "should create an annotation" do
        assert_difference -> { @check_run.annotations.count }, 1 do
          subject.call
        end
      end

      test "should not fail with invalid annotation" do
        new_updates = deep_clone(@check_run_updates)
        new_updates[:annotations] = [@invalid_annotation]

        # Assert we're not throwing ActiveRecord::RecordInvalid here
        assert_nothing_raised do
          Checks::UpdateCheckRun.call(
            check_run: @check_run,
            update_properties: new_updates,
          )
        end
      end

      test "should only remove invalid annotations" do
        new_updates = deep_clone(@check_run_updates)
        new_updates[:annotations] = [
          @invalid_annotation,
          @annotations.first,
          @annotations.first,
        ]

        assert_difference -> { @check_run.annotations.count }, 2 do
          Checks::UpdateCheckRun.call(
            check_run: @check_run,
            update_properties: new_updates,
          )
        end
      end

      test "cannot create more than the max number of annotations" do
        max_annotations = Array.new(51) { @annotations.first }
        new_updates = deep_clone(@check_run_updates)
        new_updates[:annotations] = max_annotations

        assert_raises(Checks::Errors::MaxAnnotationsExceeded) do
          Checks::UpdateCheckRun.call(
            check_run: @check_run,
            update_properties: new_updates,
          )
        end
      end
    end

    context "when updating check steps", enterprise_only: true do
      test "calls create steps service with the correct arguments" do
        Checks::CreateCheckSteps.expects(:call).with(has_entries(
          check_run: responds_with(:id, @check_run.id),
          check_steps: @steps,
          is_cloned_from_previous_run: @is_cloned_from_previous_run,
        ))

        subject.call
      end
      test "doesn't call create steps service if no steps are provided" do
        new_updates = deep_clone(@check_run_updates)
        new_updates[:check_run_steps] = []
        Checks::CreateCheckSteps.expects(:call).never

        Checks::UpdateCheckRun.call(
          check_run: @check_run,
          update_properties: new_updates,
        )
      end
      test "doesn't call create steps service if disable_dotcom_check)steps_writes returns true" do
        @check_run.stubs(:disable_dotcom_check_steps_writes?).returns(true)
        Checks::CreateCheckSteps.expects(:call).never

        subject.call
      end
    end

    context "when updating a check run with check suite concurrency" do
      test "updates a check run with check run concurrency" do
        skip if GitHub.enterprise?

        subject.call

        @check_run.reload

        concurrency = JSON.parse(@check_run.workflow_job_run.concurrency)

        assert_equal concurrency["waiting_on_resource"], { "check_run_id" => @concurrency_check_run_id }
      end
    end

    context "when updating a workflow job run" do
      test "updates workflow job run fields" do
        skip if GitHub.enterprise?

        subject.call

        @check_run.reload

        workflow_job_run = @check_run.workflow_job_run

        assert_equal workflow_job_run.job_key, @job_key
        assert_equal workflow_job_run.parent_job_id, @parent_job_id
        assert_equal workflow_job_run.runner_id, @runner_id
        assert_equal workflow_job_run.runner_name, @runner_name
        assert_equal workflow_job_run.runner_group_id, @runner_group_id
        assert_equal workflow_job_run.label_data, @labels
      end
    end

    context "highly concurrent updates" do
      500.times do |i|
        # These tests take too long to run; for local development purposes only
        next unless ENV.fetch("CHECK_RUN_CONCURRENCY_TESTS", false)

        test "does not overwrite check suite update #{i}" do
          Thread.abort_on_exception = true

          threads = [
            Thread.new { @check_suite.update!(status: "completed") },
            Thread.new { subject.call },
          ]

          threads.each(&:join)

          @check_suite.reload

          assert_equal "completed", @check_suite.status
        end
      end
    end
  end
end
