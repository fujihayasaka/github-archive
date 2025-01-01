# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectWorkflowGetItemsActionRunnerTest < GitHub::TestCase
  include MemexHelpers

  fixtures do
    enable_feature_flag(:issue_types)
    @user = create(:verified_user, login: "user1")
    @org = create(:organization, admin: @user)
    @repo = create(:repository, owner: @org)
    @label = create(:label, name: "bug", repository: @repo)
    @issue_type = @org.issue_types.find_by(name: IssueType::DEFAULTS.first[:name])

    @apostrophe_label = create(:label, name: "won't fix", repository: @repo)
    @whitespace_label = create(:label, name: "good first issue", repository: @repo)
    @project = create(:memex_project, owner: @org)
    @issue = create(:issue, repository: @repo, labels: [@label], assignees: [@user], issue_type: @issue_type)
    @pr = create(:pull_request, :disable_disk_access, repository: @repo, user: @user, labels: [@label])
  end

  context "manual runs" do
    test "should raise NotImplementedError when manual run is true" do
      assert_raises(NotImplementedError) do
        MemexProjectWorkflowAction::Runner.run(
          action: build_action("is:issue"),
          actor: @user,
          manual_run: true,
          content_types: ["Issue"],
          input: nil,
          tags: ["topic:github.memex_automation.v0.IssueCreateEvent"],
        )
      end
    end
  end

  context "filtering" do
    # This test is skipped on enterprise due to undiagnosed flakiness, but it is still valuable to run it in other
    # environments where the test does not flake.
    test "should return issue when it matches the filter", skip_enterprise: true do
      filtered_items = run_action(query: "is:issue is:open label:bug", content_types: ["Issue"], input: [@issue])

      assert_equal [@issue], filtered_items
    end

    test "should return pr when it matches the filter" do
      filtered_items = run_action(query: "is:pr is:open label:bug", content_types: ["PullRequest"], input: [@pr])

      assert_equal [@pr], filtered_items
    end

    test "should return issue with apostrophe if it matches the filter" do
      issue = create(:issue, repository: @repo, labels: [@apostrophe_label])
      filtered_items = run_action(query: "is:issue is:open label:\"won't fix\"", content_types: ["Issue"], input: [issue])

      assert_equal [issue], filtered_items
    end

    test "should return issue with whitespace if it matches the filter" do
      issue = create(:issue, repository: @repo, labels: [@whitespace_label])
      filtered_items = run_action(query: "is:issue is:open label:\"good first issue\"", content_types: ["Issue"], input: [issue])

      assert_equal [issue], filtered_items
    end

    test "should return issues with any kind of label if it matches the filter" do
      issue = create(:issue, repository: @repo, labels: [@whitespace_label, @apostrophe_label, @label])
      filtered_items = run_action(
        query: "is:issue is:open label:\"good first issue\",\"won\'t fix\",bug",
        content_types: ["Issue"],
        input: [issue]
      )

      assert_equal [issue], filtered_items
    end

    test "should return item if last_updater can write to project and repo is public" do
      other_repo = create(:public_repository)
      other_label = create(:label, name: "bug", repository: other_repo)
      other_issue = create(:issue, repository: other_repo, labels: [other_label])

      filtered_items = run_action(query: "is:issue is:open label:bug", content_types: ["Issue"], input: [other_issue], repository_id: other_repo.id)

      assert_equal [other_issue], filtered_items
    end

    test "should return nothing if last_updater cannot write to project" do
      last_updater = create(:user)
      @repo.add_member(last_updater)
      filtered_items = run_action(query: "label:bug", content_types: %w[PullRequest Issue], input: [@pr, @issue], last_updater: last_updater)
      assert_empty filtered_items
    end

    test "should return nothing if last_updater cannot read repo" do
      last_updater = create(:user)
      @repo.update(private: true)
      @project.grant_role(last_updater, :writer)
      filtered_items = run_action(query: "label:bug", content_types: %w[PullRequest Issue], input: [@pr, @issue], last_updater: last_updater)
      assert_empty filtered_items
    end

    test "should not return issue when it matches the filter but is already in the project" do
      issue_in_project = create(:issue, repository: @repo, labels: [@label]).tap do |issue|
        create(:memex_project_item, content: issue, memex_project: @project, creator: @user)
      end
      filtered_items = run_action(query: "is:pr is:open label:bug", content_types: ["Issue"], input: [issue_in_project])

      assert_empty filtered_items
    end

    test "should not return pr when it matches the filter but is already in the project" do
      pr_in_project = create(
        :pull_request,
        :disable_disk_access,
        repository: @repo,
        user: @user,
        labels: [@label],
        head_ref: "ref3"
      ).tap do |pr|
        create(:memex_project_item, content: pr, memex_project: @project, creator: @user)
      end
      filtered_items = run_action(query: "is:pr is:open label:bug", content_types: ["PullRequest"], input: [pr_in_project])

      assert_empty filtered_items
    end

    test "should return items that match free text" do
      issue = create(:issue, repository: @repo, title: "This is a bug")
      issue2 = create(:issue, repository: @repo, title: "We should fix this bug")
      pr = create(
        :pull_request,
        :disable_disk_access,
        repository: @repo,
        user: @user,
        head_ref: "ref4",
        title: "This is fixing a bug"
      )

      filtered_items = run_action(query: "bug fix", content_types: %w[PullRequest Issue], input: [issue, issue2, pr])

      assert_equal [issue2, pr], filtered_items
    end

    context "update events" do
      test "should return items with query fields if topic is not update event" do
        enable_feature_flag(:memex_auto_add_automation_update_event_filter)
        tags = ["topic:github.memex_automation.v0.IssueCreateEvent"]
        filtered_items = run_action(query: "is:issue is:open label:bug", content_types: ["Issue"], input: [@issue], tags: tags)

        assert_equal [@issue], filtered_items
      end

      test "should return items if no query fields specified if topic is IssueUpdateEvent" do
        enable_feature_flag(:memex_auto_add_automation_update_event_filter)
        issue = create(:issue, repository: @repo, title: "This is a bug")
        tags = ["topic:github.memex_automation.v0.IssueUpdateEvent"]
        filtered_items = run_action(query: "is:issue is:open", content_types: ["Issue"], input: [issue], tags: tags)

        assert_equal [issue], filtered_items
      end

      test "should not return items if has label query field specified and topic is IssueUpdateEvent" do
        enable_feature_flag(:memex_auto_add_automation_update_event_filter)
        tags = ["topic:github.memex_automation.v0.IssueUpdateEvent"]
        filtered_items = run_action(query: "is:issue is:open label:bug", content_types: ["Issue"], input: [@issue], tags: tags)

        assert_empty filtered_items
      end

      test "should not return items if has assignee query field specified and topic is IssueUpdateEvent" do
        enable_feature_flag(:memex_auto_add_automation_update_event_filter)
        tags = ["topic:github.memex_automation.v0.IssueUpdateEvent"]
        filtered_items = run_action(query: "is:issue is:open assignee:user1", content_types: ["Issue"], input: [@issue], tags: tags)

        assert_empty filtered_items
      end

      test "should not return items if has assignee & label query fields specified and topic is IssueUpdateEvent" do
        enable_feature_flag(:memex_auto_add_automation_update_event_filter)
        tags = ["topic:github.memex_automation.v0.IssueUpdateEvent"]
        filtered_items = run_action(query: "is:issue is:open -label:done -assignee:user2", content_types: ["Issue"], input: [@issue], tags: tags)

        assert_empty filtered_items
      end

      test "should return items if query contains label and IssueUpdateLabel event" do
        enable_feature_flag(:memex_auto_add_automation_update_event_filter)
        tags = ["topic:github.v1.IssueUpdateLabel"]
        filtered_items = run_action(query: "is:issue is:open label:bug", content_types: ["Issue"], input: [@issue], tags: tags)

        assert_equal [@issue], filtered_items
      end

      test "should return items if query contains label and assignee and IssueUpdateLabel event" do
        enable_feature_flag(:memex_auto_add_automation_update_event_filter)
        tags = ["topic:github.v1.IssueUpdateLabel"]
        filtered_items = run_action(query: "is:issue is:open -label:done assignee:user1", content_types: ["Issue"], input: [@issue], tags: tags)

        assert_equal [@issue], filtered_items
      end

      test "should return items if query contains label and assignee and IssueUpdateAssignee event" do
        enable_feature_flag(:memex_auto_add_automation_update_event_filter)
        tags = ["topic:github.v1.IssueUpdateAssignee"]
        filtered_items = run_action(query: "is:issue is:open -label:done assignee:user1", content_types: ["Issue"], input: [@issue], tags: tags)

        assert_equal [@issue], filtered_items
      end

      test "should return items if query contains assignee and IssueUpdateAssignee event" do
        enable_feature_flag(:memex_auto_add_automation_update_event_filter)
        tags = ["topic:github.v1.IssueUpdateAssignee"]
        filtered_items = run_action(query: "is:issue is:open assignee:user1", content_types: ["Issue"], input: [@issue], tags: tags)

        assert_equal [@issue], filtered_items
      end

      test "should return items if query field is no:assignee and IssueUpdateAssignee event" do
        enable_feature_flag(:memex_auto_add_automation_update_event_filter)
        issue = create(:issue, repository: @repo, title: "This is a bug")
        tags = ["topic:github.v1.IssueUpdateAssignee"]
        filtered_items = run_action(query: "is:issue is:open no:assignee", content_types: ["Issue"], input: [issue], tags: tags)

        assert_equal [issue], filtered_items
      end

      test "should return items if query field is -assignee:user1 and IssueUpdateAssignee event" do
        enable_feature_flag(:memex_auto_add_automation_update_event_filter)
        issue = create(:issue, repository: @repo, title: "This is a bug")
        tags = ["topic:github.v1.IssueUpdateAssignee"]
        filtered_items = run_action(query: "is:issue is:open -assignee:user1", content_types: ["Issue"], input: [issue], tags: tags)

        assert_equal [issue], filtered_items
      end

      test "should not return items if query field is not related to IssueUpdateAssignee event" do
        enable_feature_flag(:memex_auto_add_automation_update_event_filter)
        tags = ["topic:github.v1.IssueUpdateAssignee"]
        filtered_items = run_action(query: "is:issue is:open label:bug", content_types: ["Issue"], input: [@issue], tags: tags)

        assert_empty filtered_items
      end

      test "should not return items if query field is not specified on IssueUpdateAssignee event" do
        enable_feature_flag(:memex_auto_add_automation_update_event_filter)
        tags = ["topic:github.v1.IssueUpdateAssignee"]
        filtered_items = run_action(query: "is:issue is:open", content_types: ["Issue"], input: [@issue], tags: tags)

        assert_empty filtered_items
      end

      test "should return items if query contains type and IssueUpdateIssueType event" do
        enable_feature_flag(:memex_auto_add_automation_update_event_filter)
        tags = ["topic:github.v1.IssueUpdateIssueType"]
        filtered_items = run_action(query: "is:issue is:open type:task", content_types: ["Issue"], input: [@issue], tags: tags)

        assert_equal [@issue], filtered_items
      end

      test "should return items if query contains label and type and IssueUpdateIssueType event" do
        enable_feature_flag(:memex_auto_add_automation_update_event_filter)
        tags = ["topic:github.v1.IssueUpdateIssueType"]
        filtered_items = run_action(query: "is:issue is:open -label:done type:task", content_types: ["Issue"], input: [@issue], tags: tags)

        assert_equal [@issue], filtered_items
      end

      test "should return items if query field is no:type and IssueUpdateIssueType event" do
        enable_feature_flag(:memex_auto_add_automation_update_event_filter)
        issue = create(:issue, repository: @repo, title: "This is a bug")
        tags = ["topic:github.v1.IssueUpdateIssueType"]
        filtered_items = run_action(query: "is:issue is:open no:type", content_types: ["Issue"], input: [issue], tags: tags)

        assert_equal [issue], filtered_items
      end

      test "should return items if query field is -type:task and IssueUpdateIssueType event" do
        enable_feature_flag(:memex_auto_add_automation_update_event_filter)
        issue = create(:issue, repository: @repo, title: "This is a bug")
        tags = ["topic:github.v1.IssueUpdateIssueType"]
        filtered_items = run_action(query: "is:issue is:open -type:task", content_types: ["Issue"], input: [issue], tags: tags)

        assert_equal [issue], filtered_items
      end

      test "should not return items if query field is not related to IssueUpdateIssueType event" do
        enable_feature_flag(:memex_auto_add_automation_update_event_filter)
        tags = ["topic:github.v1.IssueUpdateIssueType"]
        filtered_items = run_action(query: "is:issue is:open label:bug", content_types: ["Issue"], input: [@issue], tags: tags)

        assert_empty filtered_items
      end

      test "should not return items if query field is not specified on IssueUpdateIssueType event" do
        enable_feature_flag(:memex_auto_add_automation_update_event_filter)
        tags = ["topic:github.v1.IssueUpdateIssueType"]
        filtered_items = run_action(query: "is:issue is:open", content_types: ["Issue"], input: [@issue], tags: tags)

        assert_empty filtered_items
      end
    end
  end

  private

  def build_action(query, last_updater: @user, repository_id: @repo.id)
    workflow = create(:memex_project_workflow, memex_project: @project)
    action = MemexProjectWorkflowAction.new(
      arguments: { "query" => query, "repositoryId" => repository_id },
      action_type: :get_items,
      workflow: workflow,
      last_updater: last_updater
    )
    workflow.actions << action
    action
  end

  def run_action(query:, content_types:, input:, last_updater: @user, repository_id: @repo.id, tags: ["topic:github.memex_automation.v0.IssueCreateEvent"])
    MemexProjectWorkflowAction::Runner.run(
      action: build_action(query, last_updater: last_updater, repository_id: repository_id),
      actor: @user,
      manual_run: false,
      content_types: content_types,
      input: input,
      tags: tags,
    )
  end
end
