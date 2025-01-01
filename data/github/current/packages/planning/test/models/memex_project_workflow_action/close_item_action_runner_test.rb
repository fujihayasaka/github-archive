# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectWorkflowCloseItemActionRunnerTest < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    GitHub.flipper[:disabled_global_apps].disable

    @user = create(:verified_user)
    @user_repo = create(:repository, owner: @user)
    @user_project = create(:memex_project, owner: @user)
    @user_issue, @issue_in_user_project = create_project_item_with_issue(repo: @user_repo, project: @user_project)
    @user_pr, @pr_in_user_project = create_project_item_with_pull_request(repo: @user_repo, project: @user_project)
    @user_close_items_action = create_close_items_action(project: @user_project)

    @org = create(:organization, admin: @user)
    @org_repo = create(:repository, owner: @org)
    @org_project = create(:memex_project, owner: @org)
    @org_issue, @issue_in_org_project = create_project_item_with_issue(repo: @org_repo, project: @org_project)
    @org_pr, @pr_in_org_project = create_project_item_with_pull_request(repo: @org_repo, project: @org_project)
    @org_close_items_action = create_close_items_action(project: @org_project)

    make_trusted_oauth_apps_owner
    integration = Apps::Privileged::MemexAutomation.seed_database!
    # Ensures that the newly created internal App has its production
    # configuration loaded in the Apps::Privileged::Registry.
    PrivilegedAppHelper.reconfigure_privileged_app(app_alias: :memex_automation, app: integration)
    Apps::Privileged::MemexAutomation.reload!
  end

  setup do
    @tags = ["foo:bar"]

    assert_with_user_and_organization do |_, _, pr, _, issue, _|
      T.must(pr.issue).reopen! if pr.closed?
      issue.reopen! if issue.closed?
    end
  end

  test "closes if actor is a member of org with permissions" do
    refute @org_issue.closed?

    result = MemexProjectWorkflowAction::CloseItemActionRunner.run(
      action: @org_close_items_action,
      input: [@issue_in_org_project],
      actor: @user,
      trigger_type: "project_item_column_update",
      tags: @tags
    )

    assert_equal 1, result.count
    assert @org_issue.reload.closed?
  end

  test "closes only issue items & skips pull request items" do
    assert_with_user_and_organization do |close_items_action, pr_item, pr, issue_item, issue, _|
      refute issue.closed?
      refute pr.closed?

      result = run_workflow(action: close_items_action, input: [pr_item, issue_item])

      # verify that the action runner returns an output for the next possible action
      assert_equal 1, result.count
      result.each do |project_item|
        assert T.must(project_item.content).closed?
      end

      # verify closing was saved to the database
      assert issue.reload.closed?
      refute pr.reload.closed?
    end

    assert_dogstats_increment(
      2,
      MemexHydroProjectAutomation::Instrumentation::PipedActions::METRIC_TRIGGERED,
      tags: [
        "trigger_type:project_item_column_update",
        "runner:piped",
        "action_type:close_item",
      ] + @tags
    )

    assert_dogstats_distribution(
      2,
      MemexHydroProjectAutomation::Instrumentation::PipedActions::METRIC_DURATION,
      tags: [
        "trigger_type:project_item_column_update",
        "runner:piped",
        "action_type:close_item",
      ] + @tags
    )

    # 1 log for user, 1 log for organization
    assert_dogstats_increment(
      2,
      MemexHydroProjectAutomation::Instrumentation::PipedActions::METRIC_SKIPPED,
      tags: [
        "trigger_type:project_item_column_update",
        "runner:piped",
        "action_type:close_item",
        "reason:#{MemexHydroProjectAutomation::Instrumentation::PipedActions::REASON_IS_NOT_AN_ISSUE}",
      ] + @tags
    )
  end

  test "skips draft issues" do
    assert_with_user_and_organization do |close_items_action, _, _, issue_item, _, project|
      draft = create(:memex_project_item, content: create(:draft_issue), memex_project: project)
      result = run_workflow(action: close_items_action, input: [draft, issue_item])

      assert_equal 1, result.count
    end

    # 1 log for user, 1 log for organization
    assert_dogstats_increment(
      2,
      MemexHydroProjectAutomation::Instrumentation::PipedActions::METRIC_SKIPPED,
      tags: [
        "trigger_type:project_item_column_update",
        "runner:piped",
        "action_type:close_item",
        "reason:#{MemexHydroProjectAutomation::Instrumentation::PipedActions::REASON_DOES_NOT_HAVE_CONTENT}",
      ] + @tags
    )
  end

  test "skips if issue is already closed" do
    assert_with_user_and_organization do |close_items_action, _, _, issue_item, issue, _|
      issue.close(@user)

      result = run_workflow(action: close_items_action, input: [issue_item])
      assert_equal 0, result.count
    end

    # 1 log for user, 1 log for organization
    assert_dogstats_increment(
      2,
      MemexHydroProjectAutomation::Instrumentation::PipedActions::METRIC_SKIPPED,
      tags: [
        "trigger_type:project_item_column_update",
        "runner:piped",
        "action_type:close_item",
        "reason:#{MemexHydroProjectAutomation::Instrumentation::PipedActions::REASON_CANNOT_BE_CLOSED}",
      ] + @tags
    )
  end

  test "does not close if actor is a bot" do
    assert_with_user_and_organization do |close_items_action, _, _, issue_item, issue, _|
      refute issue.closed?

      bot = create(:bot)

      result = MemexProjectWorkflowAction::CloseItemActionRunner.run(
        action: close_items_action,
        input: [issue_item],
        actor: bot,
        trigger_type: "project_item_column_update",
        tags: @tags
      )

      assert_equal 0, result.count
      refute issue.reload.closed?
    end
  end

  test "does not close if actor does not have write access" do
    assert_with_user_and_organization do |close_items_action, _, _, issue_item, issue, _|
      refute issue.closed?

      rando = create(:verified_user)

      result = MemexProjectWorkflowAction::CloseItemActionRunner.run(
        action: close_items_action,
        input: [issue_item],
        actor: rando,
        trigger_type: "project_item_column_update",
        tags: @tags
      )
      assert_equal 0, result.count
      refute issue.reload.closed?
    end

    assert_dogstats_increment(
      2,
      MemexHydroProjectAutomation::Instrumentation::PipedActions::METRIC_SKIPPED,
      tags: [
        "trigger_type:project_item_column_update",
        "runner:piped",
        "action_type:close_item",
        "reason:#{MemexHydroProjectAutomation::Instrumentation::PipedActions::REASON_NO_ACCESS}",
      ] + @tags
    )
  end

  private

  sig do
    params(
      block: T.proc.params(
        arg0: MemexProjectWorkflowAction,
        arg1: MemexProjectItem,
        arg2: PullRequest,
        arg3: MemexProjectItem,
        arg4: Issue,
        arg5: MemexProject
      ).void
    ).void
  end
  def assert_with_user_and_organization(&block)
    [
      [@org_close_items_action, @pr_in_org_project, @org_pr, @issue_in_org_project, @org_issue, @org_project],
      [@user_close_items_action, @pr_in_user_project, @user_pr, @issue_in_user_project, @user_issue, @user_project]
    ].each do |close_items_action, pr_item, pr, issue_item, issue, project|
      block.call(close_items_action, pr_item, pr, issue_item, issue, project)
    end
  end

  sig do
    params(
      repo: Repository, project: MemexProject, creator: User
    ).returns(T::Array[T.any(Issue, MemexProjectItem)])
  end
  def create_project_item_with_issue(repo:, project:, creator: @user)
    issue = create(:issue, repository: repo)
    item = create(:memex_project_item, content: issue, memex_project: project, creator: creator)
    status_column = project.status_column
    done_option_id = status_column&.settings["options"].find { |o| o["name"] == "Done" }["id"]
    item.set_column_value(status_column, done_option_id, creator)

    [issue, item]
  end

  sig do
    params(
      repo: Repository, project: MemexProject, creator: User
    ).returns(T::Array[T.any(PullRequest, MemexProjectItem)])
  end
  def create_project_item_with_pull_request(repo:, project:, creator: @user)
    pr = create(
      :pull_request,
      :disable_disk_access,
      repository: repo,
      user: creator,
      head_ref: "ref3"
    )
    item = create(:memex_project_item, content: pr, memex_project: project, creator: creator)
    status_column = project.status_column
    done_option_id = status_column&.settings["options"].find { |o| o["name"] == "Done" }["id"]
    item.set_column_value(status_column, done_option_id, creator)

    [pr, item]
  end

  sig { params(project: MemexProject, last_updater: User).returns(MemexProjectWorkflowAction) }
  def create_close_items_action(project:, last_updater: @user)
    workflow = create(:memex_project_workflow, memex_project: project, skip_action_build: true)
    create(
      :memex_project_workflow_action,
      :with_arguments,
      workflow:
      workflow,
      action_type: :close_item,
      arguments: {},
      last_updater: last_updater
    )
  end

  sig do
    params(
      action: MemexProjectWorkflowAction,
      input: T::Array[MemexProjectItem]
    ).returns(
      T::Array[MemexProjectItem]
    )
  end
  def run_workflow(action:, input:)
    MemexProjectWorkflowAction::CloseItemActionRunner.run(
      action: action,
      input: input,
      actor: @user,
      trigger_type: "project_item_column_update",
      tags: @tags
    )
  end
end
