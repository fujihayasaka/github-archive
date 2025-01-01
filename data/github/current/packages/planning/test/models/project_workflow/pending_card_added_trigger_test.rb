# typed: true
# frozen_string_literal: true

require "test_helper"

class IssuePendingCardAddedTriggerAndPrPendingCardAddedTriggerTest < GitHub::TestCase
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
  end

  setup do
    example_repo :pull_request_source, @repo
    example_repo :pull_request_fork,   @fork
    GitHub.context.push(actor_id: @owner.id)
    self.perform_enqueued_jobs = true # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
  end

  teardown do
    self.perform_enqueued_jobs = false # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
  end

  def create_column_with_workflow(limit_to:)
    column = create(:project_column, project: @project)
    trigger_type = case limit_to
    when "Issue"
      ProjectWorkflow::ISSUE_PENDING_CARD_ADDED_TRIGGER
    when "PullRequest"
      ProjectWorkflow::PR_PENDING_CARD_ADDED_TRIGGER
    end
    @project.project_workflows.set_workflow(creator: @owner, trigger_type: trigger_type, column: column)
    column
  end

  test "can create a pending issue card added workflow using helper" do
    workflow = @project.project_workflows.set_workflow(creator: @owner, trigger_type: ProjectWorkflow::ISSUE_PENDING_CARD_ADDED_TRIGGER, column: @column)
    assert_predicate workflow, :valid?
    assert_equal 1, workflow.actions.size
  end

  test "can create a pending pr card added workflow using helper" do
    workflow = @project.project_workflows.set_workflow(creator: @owner, trigger_type: ProjectWorkflow::PR_PENDING_CARD_ADDED_TRIGGER, column: @column)
    assert_predicate workflow, :valid?
    assert_equal 1, workflow.actions.size
  end

  context "issue_pending_card_added trigger" do
    test "adding an issue to a project moves its card into a column" do
      todo_column = create_column_with_workflow(limit_to: "Issue")

      card = create(:pending_project_card, project: @project, content: @issue, creator: @owner)
      card.reload

      refute_predicate card, :pending?
      assert_equal todo_column.id, card.column_id
    end

    test "adding a PR to a project does not move its card into a column" do
      create_column_with_workflow(limit_to: "Issue")

      card = create(:pending_project_card, project: @project, content: @pr.issue, creator: @owner)
      card.reload

      assert_predicate card, :pending?
    end

    test "does not trigger if project is closed" do
      create_column_with_workflow(limit_to: "Issue")
      @project.close

      card = create(:pending_project_card, project: @project, content: @issue, creator: @owner)
      card.reload

      assert_predicate card, :pending?
    end
  end

  context "pr_pending_card_added trigger" do
    test "adding a PR to a project moves its card into a column" do
      todo_column = create_column_with_workflow(limit_to: "PullRequest")

      card = create(:pending_project_card, project: @project, content: @pr.issue, creator: @owner)
      card.reload

      refute_predicate card, :pending?
      assert_equal todo_column.id, card.column_id
    end

    test "adding an issue to a project does not move its card into a column" do
      create_column_with_workflow(limit_to: "PullRequest")

      card = create(:pending_project_card, project: @project, content: @issue, creator: @owner)
      card.reload

      assert_predicate card, :pending?
    end

    test "does not trigger if project is closed" do
      create_column_with_workflow(limit_to: "PullRequest")
      @project.close

      card = create(:pending_project_card, project: @project, content: @pr.issue, creator: @owner)
      card.reload

      assert_predicate card, :pending?
    end
  end
end
