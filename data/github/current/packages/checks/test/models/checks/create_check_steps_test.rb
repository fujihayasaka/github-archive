# typed: true
# frozen_string_literal: true

require "test_helper"

class Checks::CreateCheckStepsTest < GitHub::TestCase
  setup do
    GitHub.stubs(:actions_enabled?).returns(true)
  end

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

    second_check_step = @check_run.steps.find_by(number: 1)
    @updated_check_step_name = "updated name"
    @updated_check_step_status = CheckStep.statuses[:queued]
    @updated_check_step_complete_log_url = "https://example.com/log"
    @updated_check_step_complete_log_lines = 10

    @is_cloned_from_previous_run = false

    @second_check_step_updates = {
      number: second_check_step.number,
      external_id: second_check_step.external_id,
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
  end

  def subject
    Checks::CreateCheckSteps.new(
      check_run: @check_run,
      is_cloned_from_previous_run: @is_cloned_from_previous_run,
      check_steps: @steps,
      steps_batch_size: 100,
    )
  end


  context ".call" do
    test "should report the steps count" do
      GitHub.dogstats.expects(:count).with("#{Checks::CreateCheckSteps::STATS_PREFIX}.check_steps_count", 2, tags: ["is_cloned_from_previous_run:false"])
      subject.call
    end

    test "does not accidentally update check run" do
      original_status = @check_run.status
      @check_run.status = "completed"
      subject.call

      @check_run.reload
      assert_equal @check_run.status, original_status
    end

    test "should update an existing check step" do
      subject.call

      updated_step = @check_run.steps.find_by(number: 1)

      assert_equal updated_step.name, @updated_check_step_name
      assert_equal updated_step.status, "queued"
      assert_equal updated_step.completed_log_url, @updated_check_step_complete_log_url
      assert_equal updated_step.completed_log_lines, @updated_check_step_complete_log_lines
      assert_equal updated_step.conclusion, "success"
      assert_equal updated_step.repository_id, @repo.id
    end

    test "should update check step completed_log_url and completed_log_lines for cloned check runs" do
      check_run_original = create(:check_run, check_suite: @check_suite, display_name: @check_run.display_name)
      original_steps = @check_run.steps.map do |step|
        create(:check_step, :completed, check_run: check_run_original, number: step.number, external_id: step.external_id, completed_log_url: "http://github.com/step#{step.number}-orig", completed_log_lines: 100 + step.number)
      end

      @is_cloned_from_previous_run = true
      @steps = [
        # A step to be updated with explicit logs
        {
          number: original_steps[0].number,
          external_id: original_steps[0].external_id,
          name: "RerunStep1Updated",
          status: CheckStep.statuses[:success],
          started_at: Time.new(2019, 5, 2, 12, 0, 0).utc.iso8601,
          completed_at: Time.new(2019, 5, 2, 12, 1, 0).utc.iso8601,
          conclusion: CheckStep.conclusions[:success],
          completed_log: {
            url: "https://logs.github.com/some-unique-slug-step1-updated",
            lines: 111,
          },
        },
        # A step to be updated from previous
        {
          number: original_steps[1].number,
          external_id: original_steps[1].external_id,
          name: "RerunStep2Updated",
          status: CheckStep.statuses[:in_progress],
          started_at: Time.new(2019, 5, 2, 12, 2, 0).utc.iso8601,
          completed_at: Time.new(2019, 5, 2, 12, 3, 0).utc.iso8601,
          conclusion: CheckStep.conclusions[:success],
        },
        # A new step that is not cloned and does not have logs
        {
          number: 3,
          name: "RerunStep4",
          status: CheckStep.statuses[:in_progress],
          started_at: Time.new(2019, 5, 2, 12, 4, 0).utc.iso8601,
          completed_at: Time.new(2019, 5, 2, 12, 5, 0).utc.iso8601,
          conclusion: CheckStep.conclusions[:success],
        },
      ]

      subject.call

      @check_run.reload

      assert_equal @check_run.steps.count, 4

      # Always use new logs if provided
      refute_equal check_run_original.steps.first.completed_log_url, @check_run.steps.first.completed_log_url
      refute_equal check_run_original.steps.first.completed_log_lines, @check_run.steps.first.completed_log_lines

      # Use previous logs if not provided
      assert_equal check_run_original.steps[1].completed_log_url, @check_run.steps[1].completed_log_url
      assert_equal check_run_original.steps[1].completed_log_lines, @check_run.steps[1].completed_log_lines

      # Don't use previous logs if the step is new
      assert_nil @check_run.steps.last.completed_log_url
      assert_nil @check_run.steps.last.completed_log_lines
    end

    test "should create a new check step" do
      assert_difference -> { @check_run.steps.count }, 1 do
        subject.call
      end

      new_step = @check_run.steps.find_by(number: @new_step_number)

      assert_equal @new_step_data[:name], new_step.name
      assert_equal @new_step_data[:external_id], new_step.external_id
      assert_equal @new_step_data[:status], CheckStep.statuses[new_step.status]
      assert_equal @new_step_data[:conclusion], CheckStep.conclusions[new_step.conclusion]
      assert_equal @repo.id, new_step.repository_id
    end

    test "creates a larger amount of new steps" do
      last_step_number = @check_run.steps.sort_by(&:number).last.number
      steps = 10.times.map do |i|
        {
          number: last_step_number + i,
          status: CheckStep.statuses[:queued],
          external_id: "1234 #{i}",
          name: "new step #{i}",
          conclusion: CheckStep.conclusions[:neutral],
        }
      end

      subject = Checks::CreateCheckSteps.new(
        check_run: @check_run,
        is_cloned_from_previous_run: @is_cloned_from_previous_run,
        check_steps: steps,
        steps_batch_size: 2,
      )

      assert_difference -> { @check_run.steps.count }, 10 do
        subject.call
      end
    end

    test "does not query the check_runs table when creating new check steps" do
      _, queries = log_queries do
        subject.call
      end

      assert queries.none? { |q| q.digested_sql == "SELECT check_runs.* FROM check_runs WHERE check_runs.id = ? LIMIT ?" }, "Expected no check run lookup when creating check step"
    end

    test "updates a check step based on external id" do
      original_step_count = @check_run.steps.count

      @steps = [
        {
          number: 1337,
          external_id: @check_run.steps.first.external_id,
        }
      ]

      subject.call

      @check_run.reload

      refute_nil @check_run.steps.find_by(number: 1337)
      assert_equal original_step_count, @check_run.steps.count
    end
  end
end
