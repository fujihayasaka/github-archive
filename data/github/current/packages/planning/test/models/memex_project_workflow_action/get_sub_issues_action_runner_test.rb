# typed: true
# frozen_string_literal: true

require "test_helper"

class GetSubIssuesActionRunnerTest < GitHub::TestCase
  include MemexHelpers

  setup do
    GitHub.flipper[:sub_isues].enable
    @user = create(:verified_user, login: "user1")
    @org = create(:organization, admin: @user)
    @repo = create(:repository, owner: @org)
    @project = create(:memex_project, owner: @org)

    @parent_issue = create(:issue, repository: @repo)
    @sub_issue1 = create(:issue, repository: @repo)
    @sub_issue2 = create(:issue, repository: @repo)
    @parent_issue.add_sub_issue!(@sub_issue1, @user.id)
    @parent_issue.add_sub_issue!(@sub_issue2, @user.id)
    @parent_item = create(:memex_project_item, content: @parent_issue, memex_project: @project)
  end

  test "returns input if not manual run" do
    sub_issues = run_action(input: [@sub_issue1], manual_run: false)
    assert_same_elements [@sub_issue1], sub_issues
  end

  test "returns sub-issues for all parents in project if manual run" do
    sub_issues = run_action(input: nil, manual_run: true)
    assert_same_elements [@sub_issue1, @sub_issue2], sub_issues
  end

  test "ignores parents in different projects" do
    project2 = create(:memex_project, owner: @org)
    parent_issue2 = create(:issue, repository: @repo)
    sub_issue3 = create(:issue, repository: @repo)
    parent_issue2.add_sub_issue!(sub_issue3, @user.id)
    create(:memex_project_item, content: parent_issue2, memex_project: project2)

    sub_issues = run_action(input: nil)
    assert_same_elements [@sub_issue1, @sub_issue2], sub_issues
  end

  test "queries once for parents and once for sub-issues only" do
    parent_issue2 = create(:issue, repository: @repo)
    sub_issue3 = create(:issue, repository: @repo)
    parent_issue2.add_sub_issue!(sub_issue3, @user.id)
    create(:memex_project_item, content: parent_issue2, memex_project: @project)

    parent_issue3 = create(:issue, repository: @repo)
    sub_issue4 = create(:issue, repository: @repo)
    parent_issue3.add_sub_issue!(sub_issue4, @user.id)
    create(:memex_project_item, content: parent_issue3, memex_project: @project)

    # once to get parents, once to prefill sub-issues
    assert_query_count_per_table({
      issues: 2,
    }) do
      run_action(input: nil)
    end
  end

  private

  def build_action(last_updater: @user)
    workflow = create(:memex_project_workflow, memex_project: @project)
    action = MemexProjectWorkflowAction.new(
      action_type: :get_sub_issues,
      workflow: workflow,
      last_updater: last_updater
    )
    workflow.actions << action
    action
  end

  def run_action(input:, manual_run: true, last_updater: @user)
    MemexProjectWorkflowAction::Runner.run(
      action: build_action(last_updater: last_updater),
      actor: @user,
      manual_run: manual_run,
      input: input,
    )
  end
end
