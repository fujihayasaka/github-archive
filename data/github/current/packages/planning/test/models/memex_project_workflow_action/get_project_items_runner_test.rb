# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectWorkflowGetProjectItemsRunnerTest < GitHub::TestCase
  extend T::Sig

  fixtures do
    @user = create(:user)
    @org = create(:organization)
    @repo = create(:repository, owner: @org)
    @project = create(:memex_project, owner: @org)

    @draft_issue = create(:draft_issue).freeze
    @draft_issue_item = create(:memex_project_item, content_type: "DraftIssue", content_id: @draft_issue.id, memex_project: @project)

    @draft_pr = create(:pull_request, :disable_disk_access, repository: @repo, user: @user, draft: true, head_ref: "ref0").freeze
    @draft_pr_item = create(:memex_project_item, content_type: "PullRequest", content_id: @draft_pr.id, memex_project: @project)

    @open_issue = create(:issue, repository: @repo, state: "opened").freeze
    @open_issue_item = create(:memex_project_item, content_type: "Issue", content_id: @open_issue.id, memex_project: @project)

    @open_archived_issue = create(:issue, repository: @repo, state: "opened").freeze
    @open_archived_issue_item = create(:memex_project_item, content_type: "Issue", content_id: @open_archived_issue.id, memex_project: @project, archiver: @user, archived_at: Time.now)

    @closed_issue = create(:issue, repository: @repo, state: "closed", state_reason: :not_planned).freeze
    @closed_issue_item = create(:memex_project_item, content_type: "Issue", content_id: @closed_issue.id, memex_project: @project)

    @open_pr = create(:pull_request, :disable_disk_access, repository: @repo, user: @user).freeze
    @open_pr_item = create(:memex_project_item, content_type: "PullRequest", content_id: @open_pr.id, memex_project: @project)

    @open_archived_pr = create(:pull_request, :disable_disk_access, repository: @repo, user: @user, head_ref: "something").freeze
    @open_archived_pr_item = create(:memex_project_item, content_type: "PullRequest", content_id: @open_archived_pr.id, memex_project: @project, archiver: @user, archived_at: Time.now)

    @closed_pr = create(:pull_request, :closed, :disable_disk_access, repository: @repo, user: @user, head_ref: "ref1").freeze
    @closed_pr_item = create(:memex_project_item, content_type: "PullRequest", content_id: @closed_pr.id, memex_project: @project)

    @merged_pr = create(:pull_request, :merged, :disable_disk_access, repository: @repo, user: @user, head_ref: "ref2").freeze
    @merged_pr_item = create(:memex_project_item, content_type: "PullRequest", content_id: @merged_pr.id, memex_project: @project)
  end

  sig { params(field_id: Integer, field_option_id: String).returns(MemexProjectWorkflowAction) }
  def build_field_action(field_id, field_option_id)
    workflow = create(:memex_project_workflow, :skip_validations, memex_project: @project, name: name)
    action = MemexProjectWorkflowAction.new(
      arguments: { "fieldId" => field_id, "fieldOptionId" => field_option_id, "query" => "" },
      action_type: :get_project_items,
      workflow: workflow
    )
    workflow.actions << action
    action
  end

  def build_action(query, name = "Closed")
    workflow = create(:memex_project_workflow, :skip_validations, memex_project: @project, name: name)
    action = MemexProjectWorkflowAction.new(
      arguments: { "query" => query },
      action_type: :get_project_items,
      workflow: workflow
    )
    workflow.actions << action
    action
  end

  def run_action_manually(action, content_types)
    MemexProjectWorkflowAction::Runner.run(
      action: action,
      actor: @user,
      manual_run: true,
      content_types: content_types,
      input: nil
    )
  end

  context "integrations - query" do
    test "handles title queries" do
      issue = create(:issue, title: "find me", repository: @repo, state: "opened").freeze
      issue_item = create(:memex_project_item, content_type: "Issue", content_id: issue.id, memex_project: @project)
      output = run_action_manually(build_action("is:open find me"), ["Issue"])
      assert_includes output, issue_item, "should find the project item referencing the issue by title"
    end
  end

  context "integrations - field" do
    test "handles status field - match" do
      status_column = @project.status_column
      status_column_value = status_column.settings["options"][0]["id"]
      issue = create(:issue, repository: @repo).freeze
      issue_item = create(:memex_project_item, content_type: "Issue", content_id: issue.id, memex_project: @project)
      issue_item.set_column_value(status_column, status_column_value, @user)

      output = run_action_manually(build_field_action(status_column.id, status_column_value), ["Issue"])
      assert_includes output, issue_item, "should find the project item matching the status value"
    end

    test "handles status field - no match" do
      status_column = @project.status_column
      status_column_value = status_column.settings["options"][0]["id"]
      issue = create(:issue, repository: @repo).freeze
      issue_item = create(:memex_project_item, content_type: "Issue", content_id: issue.id, memex_project: @project)

      output = run_action_manually(build_field_action(status_column.id, status_column_value), ["Issue"])
      refute_includes output, issue_item, "should not find the project item matching the status value"
    end

    test "errors if both `query` and `fieldId` are present in argument" do
      status_column = @project.status_column
      status_column_value = status_column.settings["options"][0]["id"]

      workflow = create(:memex_project_workflow, :skip_validations, memex_project: @project, name: name)
      action = MemexProjectWorkflowAction.new(
        arguments: { "fieldId" => status_column.id, "fieldOptionId" => status_column_value, "query" => "is:issue" },
        action_type: :get_project_items,
        workflow: workflow
      )
      workflow.actions << action
      assert_raises_with_message(ArgumentError, "Cannot specify both a field and a query in a get_project_items action") do
        run_action_manually(action, nil)
      end
    end
  end

  context "manual runs - query" do
    test "errors if content_types is nil" do
      assert_raises_with_message(ArgumentError, "manual run for get_project_items requires content_types") do
        run_action_manually(build_action(""), nil)
      end
    end

    test "no items are found if content_types is empty" do
      output = run_action_manually(build_action(""), [])
      assert_equal 0, output.count
    end

    test "find items in the project correctly based on the content_types and the query" do
      output = run_action_manually(build_action("is:closed"), ["Issue"])
      assert_equal 1, output.count
      assert output.first.id == @closed_issue_item.id

      output = run_action_manually(build_action("is:closed", name: "closed-1"), ["PullRequest"])
      assert_equal 2, output.count
      assert [@merged_pr_item.id, @closed_pr_item.id].include?(output.first.id)
      assert [@merged_pr_item.id, @closed_pr_item.id].include?(output.second.id)

      output = run_action_manually(build_action("is:closed", name: "closed-2"), %w[Issue PullRequest])
      assert_equal 3, output.count
      assert [@merged_pr_item.id, @closed_issue_item.id, @closed_pr_item.id].include?(output.first.id)
      assert [@merged_pr_item.id, @closed_issue_item.id, @closed_pr_item.id].include?(output.second.id)
      assert [@merged_pr_item.id, @closed_issue_item.id, @closed_pr_item.id].include?(output.third.id)

      output = run_action_manually(build_action("is:open", name: "closed-3"), ["Issue"])
      assert_equal 2, output.count
      assert [@open_issue_item.id, @draft_issue_item.id].include?(output.first.id)
      assert [@open_issue_item.id, @draft_issue_item.id].include?(output.second.id)

      output = run_action_manually(build_action("is:open", name: "closed-4"), ["PullRequest"])
      assert_equal 2, output.count
      assert [@open_pr_item.id, @draft_pr_item.id].include?(output.first.id)
      assert [@open_pr_item.id, @draft_pr_item.id].include?(output.second.id)

      output = run_action_manually(build_action("is:open", name: "closed-5"), %w[Issue PullRequest])
      assert_equal 4, output.count
      assert [@open_issue_item.id, @draft_issue_item.id, @open_pr_item.id, @draft_pr_item.id].include?(output.first.id)
      assert [@open_issue_item.id, @draft_issue_item.id, @open_pr_item.id, @draft_pr_item.id].include?(output.second.id)
      assert [@open_issue_item.id, @draft_issue_item.id, @open_pr_item.id, @draft_pr_item.id].include?(output.third.id)
      assert [@open_issue_item.id, @draft_issue_item.id, @open_pr_item.id, @draft_pr_item.id].include?(output.fourth.id)

      output = run_action_manually(build_action("is:closed reason:\"not planned\"", name: "closed-6"), %w[Issue PullRequest])
      assert_equal 1, output.count
      assert @closed_issue_item.id == output.first.id
    end
  end
end
