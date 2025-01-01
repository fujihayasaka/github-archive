# typed: true
# frozen_string_literal: true

require "test_helper"

class IssueReopenedTriggerAndPrReopenedTriggerTest < GitHub::TestCase
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
    @pr_card = create(:project_card, column: @column, content: @pr.issue)

    @issue.close
    @pr.close
  end

  setup do
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
      ProjectWorkflow::ISSUE_REOPENED_TRIGGER
    when "PullRequest"
      ProjectWorkflow::PR_REOPENED_TRIGGER
    end

    @project.project_workflows.set_workflow(creator: @owner, trigger_type: trigger_type, column: column)
    column
  end

  test "can create an issue reopened workflow using helper" do
    workflow = @project.project_workflows.set_workflow(creator: @owner, trigger_type: ProjectWorkflow::ISSUE_REOPENED_TRIGGER, column: @column)
    assert_predicate workflow, :valid?
    assert_equal 1, workflow.actions.size
  end

  test "can create a pr reopened workflow using helper" do
    workflow = @project.project_workflows.set_workflow(creator: @owner, trigger_type: ProjectWorkflow::PR_REOPENED_TRIGGER, column: @column)
    assert_predicate workflow, :valid?
    assert_equal 1, workflow.actions.size
  end

  context "issue_reopened trigger" do
    test "reopening an issue moves its card into a column" do
      todo_column = create_column_with_workflow(limit_to: "Issue")

      assert_equal @column.id, @issue_card.column_id
      @issue.open(@owner)
      @issue_card.reload

      assert_equal todo_column.id, @issue_card.column_id
    end

    test "reopening a PR does not move its card into a column" do
      Spokesd.enable_spokesd

      create_column_with_workflow(limit_to: "Issue")

      assert_equal @column.id, @pr_card.column_id
      @pr.open(@owner)
      @pr_card.reload

      assert_equal @column.id, @pr_card.column_id
    end

    test "does not trigger if project is closed" do
      create_column_with_workflow(limit_to: "Issue")
      @project.close

      assert_equal @column.id, @issue_card.column_id
      @issue.open(@owner)
      @issue_card.reload

      assert_equal @column.id, @pr_card.column_id
    end

    test "does not trigger if the card is archived" do
      create_column_with_workflow(limit_to: "Issue")
      @issue_card.archive

      assert_equal @column.id, @issue_card.column_id
      @issue.open(@owner)
      @issue_card.reload

      assert_equal @column.id, @issue_card.column_id
    end
  end

  context "pr_reopened trigger" do
    test "reopening a PR moves its card into a column" do
      Spokesd.enable_spokesd

      todo_column = create_column_with_workflow(limit_to: "PullRequest")

      assert_equal @column.id, @pr_card.column_id
      @pr.open(@owner)
      @pr_card.reload

      assert_equal todo_column.id, @pr_card.column_id
    end

    test "reopening an issue does not move its card into a column" do
      create_column_with_workflow(limit_to: "PullRequest")

      assert_equal @column.id, @issue_card.column_id
      @issue.open(@owner)
      @issue_card.reload

      assert_equal @column.id, @issue_card.column_id
    end

    test "does not trigger if project is closed" do
      Spokesd.enable_spokesd

      create_column_with_workflow(limit_to: "PullRequest")
      @project.close

      assert_equal @column.id, @pr_card.column_id
      @pr.open(@owner)
      @pr_card.reload

      assert_equal @column.id, @pr_card.column_id
    end

    test "does not trigger if the card is archived" do
      Spokesd.enable_spokesd

      create_column_with_workflow(limit_to: "PullRequest")
      @pr_card.archive

      assert_equal @column.id, @pr_card.column_id
      @pr.open(@owner)
      @pr_card.reload

      assert_equal @column.id, @pr_card.column_id
    end
  end
end
