# typed: true
# frozen_string_literal: true

require "test_helper"

class ProjectWorkflowTest < GitHub::TestCase
  include GitHub::PullRequestTestHelpers

  fixtures do
    @owner = create(:user, login: "ari")
    @repo = create(:repository, owner: @owner, from_example: :pull_request_source)
    @forker = create(:user, login: "bwalsh")
    @fork = create(:fork_repository, forker: @forker, fork_repo: @repo, from_example: :pull_request_fork)

    issue = create(:issue, user: @forker, repository: @repo)
    @pr = PullRequest.create_for(@repo, {
      base:  "master",
      head:  "#{@fork.user}:topic",
      user:  issue.user,
      issue: issue,
    })

    @project = create(:project, owner: @repo)
    @column = create(:project_column, project: @project)
    @issue = create(:issue, repository: @repo)

    @issue_card = create(:project_card, column: @column, content: @issue)
  end

  setup do
    # PR merge state persists between runs so we need to re-apply
    # example_repo here to make sure things are in the clean slate
    # state for tests
    example_repo :pull_request_source, @repo
    example_repo :pull_request_fork,   @fork
    GitHub.context.push(actor_id: @owner.id)
    self.perform_enqueued_jobs = true # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
  end

  teardown do
    self.perform_enqueued_jobs = false # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
  end

  test "can create a workflow" do
    workflow = create :project_workflow
    assert_predicate workflow, :valid?
  end

  test "updating a workflow updates the last_updater actor" do
    done_column = create(:project_column, project: @project, name: "done")
    workflow = create(:project_workflow, trigger_type: ProjectWorkflow::ISSUE_CLOSED_TRIGGER, project: @project)
    assert_nil workflow.last_updater

    workflow.set_transition_action(column: done_column, creator: @owner)
    workflow.reload
    assert_equal @owner, workflow.last_updater
  end

  test "can create a workflow with action using helper" do
    workflow = @project.project_workflows.set_workflow(creator: @owner, trigger_type: ProjectWorkflow::ISSUE_CLOSED_TRIGGER, column: @column)
    assert_predicate workflow, :present?
    assert_equal 1, workflow.actions.size
    action = workflow.actions.first
    assert_predicate action, :present?
    assert_equal "transition_to_column", action.action_type
  end

  test "changing a workflow with helper does not create two workflows " do
    workflow = @project.project_workflows.set_workflow(creator: @owner, trigger_type: ProjectWorkflow::ISSUE_CLOSED_TRIGGER, column: @column)
    assert_predicate workflow, :present?
    assert_equal 1, @project.project_workflows.size

    workflow = @project.project_workflows.set_workflow(creator: @owner, trigger_type: ProjectWorkflow::ISSUE_CLOSED_TRIGGER, column: @column)
    assert_predicate workflow, :present?
    assert_equal 1, @project.project_workflows.size
  end

  context "validate" do
    test "trigger_type is present" do
      workflow = create :project_workflow
      workflow.trigger_type = nil
      refute_predicate workflow, :valid?
    end

    test "trigger_type is valid type" do
      workflow = create :project_workflow
      workflow.trigger_type = "when_something_funny_happens"
      refute_predicate workflow, :valid?
    end

    test "creator is present" do
      workflow = create :project_workflow
      workflow.creator = nil
      refute_predicate workflow, :valid?
    end

    test "project is present" do
      workflow = create :project_workflow
      workflow.project = nil
      refute_predicate workflow, :valid?
    end
  end

  context "project" do
    test "can get a list of project workflows" do
      project_workflow_1 = create(:project_workflow, trigger_type: ProjectWorkflow::ISSUE_CLOSED_TRIGGER, project: @project)
      project_workflow_2 = create(:project_workflow, trigger_type: ProjectWorkflow::PR_PENDING_CARD_ADDED_TRIGGER, project: @project)

      assert_same_elements [project_workflow_1, project_workflow_2], @project.project_workflows
    end
  end

  context "delete" do
    test "deletes project workflow when project is deleted" do
      project_workflow = create(:project_workflow, trigger_type: ProjectWorkflow::PR_MERGED_TRIGGER, project: @project)
      assert_difference("ProjectWorkflow.count", -1) do
        @project.destroy
      end
    end

    test "does not delete project when project workflow is deleted" do
      project_workflow = create(:project_workflow, trigger_type: ProjectWorkflow::ISSUE_CLOSED_TRIGGER, project: @project)
      assert_no_difference("Project.count") do
        project_workflow.destroy
      end
    end

    test "deletes project workflow when project column is deleted" do
      project_workflow = create(:project_workflow, trigger_type: ProjectWorkflow::ISSUE_REOPENED_TRIGGER, project: @project)
      project_workflow.set_transition_action(column: @column, creator: @owner)
      assert_difference("ProjectWorkflow.count", -1) do
        @column.destroy
      end
    end

    test "does not delete project column when project workflow is deleted" do
      project_workflow = create(:project_workflow, trigger_type: ProjectWorkflow::ISSUE_CLOSED_TRIGGER, project: @project)
      project_workflow.set_transition_action(column: @column, creator: @owner)
      assert_no_difference("ProjectColumn.count") do
        project_workflow.destroy
      end
    end
  end

  context "exceptions" do
    test "raises an error if trying to call set_transition_action on a column not in project" do
      project = create(:project, owner: @repo)
      column = create(:project_column, project: project)
      workflow = create(:project_workflow, trigger_type: ProjectWorkflow::ISSUE_PENDING_CARD_ADDED_TRIGGER, project: @project)

      assert_raises(ArgumentError) do
        workflow.set_transition_action(column: column, creator: @owner)
      end
    end
  end

  context "disabled projects" do
    test "state change automation not performed when project is disabled" do
      @repo.disable_repository_projects(actor: @owner)

      done_column = create(:project_column, project: @project, name: "done")
      workflow = create(:project_workflow, trigger_type: ProjectWorkflow::ISSUE_CLOSED_TRIGGER, project: @project)
      workflow.set_transition_action(column: done_column, creator: @owner)

      assert_equal @column.id, @issue_card.column_id
      @issue.close
      @issue_card.reload

      assert_equal @column.id, @issue_card.column_id
    end

    test "pending card automation not performed when project is disabled" do
      @repo.disable_repository_projects(actor: @owner)
      issue = create(:issue, repository: @repo)

      todo_column = create(:project_column, project: @project, name: "todo")
      workflow = create(:project_workflow, trigger_type: ProjectWorkflow::PR_PENDING_CARD_ADDED_TRIGGER, project: @project)
      workflow.set_transition_action(column: todo_column, creator: @owner)
      card = create(:pending_project_card, project: @project, content: issue, creator: @owner)
      card.reload

      assert_predicate card, :pending?
    end
  end

  context "tracking" do
    test "increments counter when project workflow is created" do
      create(:project_workflow, trigger_type: ProjectWorkflow::ISSUE_CLOSED_TRIGGER, project: @project)
      assert_equal 1, GitHub.dogstats.increments("project_workflow.created").length
    end

    test "increments counter when project workflow is deleted" do
      workflow = create(:project_workflow, trigger_type: ProjectWorkflow::ISSUE_CLOSED_TRIGGER, project: @project)
      workflow.destroy
      assert_equal 1, GitHub.dogstats.increments("project_workflow.deleted").length
    end

    test "adds timing entry for how long job was enqueued" do
      done_column = create(:project_column, project: @project, name: "done")

      workflow = create(:project_workflow, trigger_type: ProjectWorkflow::ISSUE_CLOSED_TRIGGER, project: @project)
      workflow.set_transition_action(column: done_column, creator: @owner)

      assert_equal @column.id, @issue_card.column_id
      @issue.close

      timing_entry = GitHub.dogstats.distributions("job.dist.process_project_workflows.time_enqueued").first

      assert timing_entry.tags.include?("trigger_type:issue_closed")
      refute_equal 0, timing_entry.value
    end

    test "adds timing for how long it took to process single job" do
      todo_column = create(:project_column, project: @project, name: "todo")
      issue = create(:issue, repository: @repo)

      workflow = create(:project_workflow, trigger_type: ProjectWorkflow::ISSUE_PENDING_CARD_ADDED_TRIGGER, project: @project)
      workflow.set_transition_action(column: todo_column, creator: @owner)
      card = create(:pending_project_card, project: @project, content: issue, creator: @owner)

      timing_entry = GitHub.dogstats.distributions("job.dist.process_project_workflows.time").first

      assert timing_entry.tags.include?("trigger_type:issue_pending_card_added")
      refute_equal 0, timing_entry.value
    end

    test "adds timing for how long it took to process all batches" do
      todo_column = create(:project_column, project: @project, name: "todo")
      issue = create(:issue, repository: @repo)

      workflow = create(:project_workflow, trigger_type: ProjectWorkflow::ISSUE_PENDING_CARD_ADDED_TRIGGER, project: @project)
      workflow.set_transition_action(column: todo_column, creator: @owner)
      card = create(:pending_project_card, project: @project, content: issue, creator: @owner)

      timing_entry = GitHub.dogstats.distributions("job.dist.process_project_workflows.total_time").first

      assert timing_entry.tags.include?("trigger_type:issue_pending_card_added")
      refute_equal 0, timing_entry.value
    end

    test "adds count entry for number of workflows processed" do
      todo_column = create(:project_column, project: @project, name: "todo")

      workflow = create(:project_workflow, trigger_type: ProjectWorkflow::ISSUE_CLOSED_TRIGGER, project: @project)
      workflow.set_transition_action(column: todo_column, creator: @owner)

      assert_equal @column.id, @issue_card.column_id
      @issue.close

      count_entry = GitHub.dogstats.counts("job.process_project_workflows.processed").first
      assert count_entry.tags.include?("trigger_type:issue_closed")
      refute_equal 0, count_entry.value

      legacy_count_entry = GitHub.dogstats.counts("project_workflow.processed").first
      assert legacy_count_entry.tags.include?("trigger_type:issue_closed")
      refute_equal 0, legacy_count_entry.value
    end

    test "adds count entry for number of workflows processed for general scoped to issue" do
      @issue.close

      todo_column = create(:project_column, project: @project, name: "todo")

      workflow = create(:project_workflow, trigger_type: ProjectWorkflow::ISSUE_REOPENED_TRIGGER, project: @project)
      workflow.set_transition_action(column: todo_column, creator: @owner)

      assert_equal @column.id, @issue_card.column_id
      @issue.open(@owner)

      count_entry = GitHub.dogstats.counts("job.process_project_workflows.processed").last
      assert count_entry.tags.include?("trigger_type:issue_reopened")
      refute_equal 0, count_entry.value

      legacy_count_entry = GitHub.dogstats.counts("project_workflow.processed").last
      assert legacy_count_entry.tags.include?("trigger_type:issue_reopened")
      refute_equal 0, legacy_count_entry.value
    end
  end

  context "instrumentation" do
    test "instruments project workflow creation" do
      events = subscribe "project_workflow.create"
      workflow = create(:project_workflow, trigger_type: ProjectWorkflow::ISSUE_CLOSED_TRIGGER, project_column: @column)

      expected_payload = {
        project_workflow: ProjectWorkflow::ISSUE_CLOSED_TRIGGER,
        project_workflow_id: workflow.id,
        project_column: @column.name,
        project_column_id: @column.id,
        project: @project.name,
        project_id: @project.id,
        rank: 4,
      }
      assert event = events.pop, "an event was expected"
      assert_equal "project_workflow.create", event.name
      assert_equal expected_payload, event.payload
    end

    test "instruments project workflow update" do
      events = subscribe "project_workflow.update"
      workflow = create(:project_workflow, trigger_type: ProjectWorkflow::PR_MERGED_TRIGGER, project_column: @column)

      done_column = create(:project_column, project: @project, name: "done")
      workflow.set_transition_action(column: done_column, creator: @owner)

      expected_payload = {
        project_workflow: ProjectWorkflow::PR_MERGED_TRIGGER,
        project_workflow_id: workflow.id,
        project_column: done_column.name,
        project_column_id: done_column.id,
        project: @project.name,
        project_id: @project.id,
        rank: 4,
        changes: {
          old_column_id: @column.id,
          old_column_name: @column.name,
          column_id: done_column.id,
          column_name: done_column.name,
        },
      }
      assert event = events.pop, "an event was expected"
      assert_equal "project_workflow.update", event.name
      assert_equal expected_payload, event.payload
    end

    test "instruments project workflow deletion" do
      events = subscribe "project_workflow.delete"
      workflow = create(:project_workflow, trigger_type: ProjectWorkflow::ISSUE_REOPENED_TRIGGER, project: @project)
      workflow.set_transition_action(column: @column, creator: @owner)
      workflow.destroy

      expected_payload = {
        project_workflow: ProjectWorkflow::ISSUE_REOPENED_TRIGGER,
        project_workflow_id: workflow.id,
        project_column: @column.name,
        project_column_id: @column.id,
        project: @project.name,
        project_id: @project.id,
        rank: 4,
      }
      assert event = events.pop, "an event was expected"
      assert_equal "project_workflow.delete", event.name
      assert_equal expected_payload, event.payload
    end
  end
end
