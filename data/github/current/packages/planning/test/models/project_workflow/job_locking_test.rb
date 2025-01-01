# typed: true
# frozen_string_literal: true

require "test_helper"

class ProjectWorkflowJobLockingTest < GitHub::TestCase
  include GitHub::PullRequestTestHelpers

  fixtures do
    @owner = create(:user, login: "ari")
    @repo = create(:repository, owner: @owner)
    @issue_a = create(:issue, repository: @repo)
    @issue_b = create(:issue, repository: @repo)

    @project_a = create(:project, owner: @repo)
    @project_b = create(:project, owner: @repo)
    @column_a = create(:project_column, project: @project_a)
    @column_b = create(:project_column, project: @project_b)

    @issue_card_a = create(:project_card, project: @project_a, column: @column_a, content: @issue_a)
    @issue_card_b = create(:project_card, project: @project_b, column: @column_b, content: @issue_b)
  end

  setup do
    example_repo :pull_request_source, @repo
    GitHub.context.push(actor_id: @owner.id)
  end

  def create_column_with_workflow(project)
    column = create(:project_column, project: project)
    project.project_workflows.set_workflow(
      creator: @owner,
      trigger_type: ProjectWorkflow::ISSUE_CLOSED_TRIGGER,
      column: column)
    column
  end

  # sanity check
  test "can create an issue closed workflow using helper" do
    workflow = @project_a.project_workflows.set_workflow(
      creator: @owner,
      trigger_type: ProjectWorkflow::ISSUE_CLOSED_TRIGGER,
      column: @column_a)
    assert_predicate workflow, :valid?
    assert_equal 1, workflow.actions.size
  end

  # Make sure the same issue close event successfully applies to all project
  # workflows, including job queueing. This is a regression test to prevent two
  # unrelated jobs for the same type of issue event from blocking each other
  # from enqueueing a workflow job.
  test "closing an issue moves its card into all related workflow columns" do
    done_column_a = create_column_with_workflow(@project_a)
    done_column_b = create_column_with_workflow(@project_b)

    @issue_a.close
    @issue_b.close

    # Wait until all workflow jobs are queued (including resolving locks, if
    # applicable) and then process them.
    perform_enqueued_jobs only: ProcessProjectWorkflowsJob

    @issue_card_a.reload
    @issue_card_b.reload
    assert_equal done_column_a.id, @issue_card_a.column_id
    assert_equal done_column_b.id, @issue_card_b.column_id
  end
end
