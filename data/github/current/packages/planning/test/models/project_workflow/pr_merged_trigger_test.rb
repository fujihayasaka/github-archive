# typed: true
# frozen_string_literal: true

require "test_helper"

class ProjectWorkflowPrMergedTriggerTest < GitHub::TestCase
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

  def create_column_with_workflow
    column = create(:project_column, project: @project)
    @project.project_workflows.set_workflow(creator: @owner, trigger_type: ProjectWorkflow::PR_MERGED_TRIGGER, column: column)
    column
  end

  test "can create a pr merged workflow using helper" do
    workflow = @project.project_workflows.set_workflow(creator: @owner, trigger_type: ProjectWorkflow::PR_MERGED_TRIGGER, column: @column)
    assert_predicate workflow, :valid?
    assert_equal 1, workflow.actions.size
  end

  context "pr_merged trigger" do
    test "merging a PR moves its card into a column" do
      pull = create(:pull_request, repository: @repo, base_repository: @repo, head_repository: @repo, head_ref: "master-merged-topic")
      column = create(:project_column, project: @project)
      pr_card = create(:project_card, column: column, content: pull.issue)
      done_column = create_column_with_workflow

      assert_equal column.id, pr_card.column_id
      pull.merge
      pr_card.reload

      assert_equal done_column.id, pr_card.column_id
    end

    test "closing a PR does not move its card into a column" do
      create_column_with_workflow

      assert_equal @column.id, @pr_card.column_id
      @pr.close
      @pr_card.reload

      assert_equal @column.id, @pr_card.column_id
    end

    test "closing an issue does not move its card into a column" do
      create_column_with_workflow

      assert_equal @column.id, @issue_card.column_id
      @issue.close
      @issue_card.reload

      assert_equal @column.id, @issue_card.column_id
    end

    test "does not trigger if project is closed" do
      create_column_with_workflow

      @project.close
      assert_equal @column.id, @pr_card.column_id
      @pr.merge
      @pr_card.reload

      assert_equal @column.id, @pr_card.column_id
    end

    test "does not trigger if the card is archived" do
      create_column_with_workflow
      @pr_card.archive

      assert_equal @column.id, @pr_card.column_id
      @pr.merge
      @pr_card.reload

      assert_equal @column.id, @pr_card.column_id
    end
  end
end
