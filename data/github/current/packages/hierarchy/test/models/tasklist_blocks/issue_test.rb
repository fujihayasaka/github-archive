# typed: false
# frozen_string_literal: true

require "test_helper"

module TasklistBlocks
  class TasklistBlocksIssueTest < GitHub::TestCase
    include IssuesGraphTestHelpers

    context "from_proto" do
      test "initializes model from protobuf" do
        key = build_proto_key(
          owner_id: 1,
          item_id: 2,
          uuid: "1-1-1-1"
        )
        proto_issue = build_proto_issue(
          key: key,
          title: "My issue title",
          url: "https://github.com/github/github/issues/1",
          state: "open",
          state_reason: "Some reason",
          repo_name: "issues-graph",
          repo_id: 3,
          user_name: "github",
          number: 4,
          position: 1234,
          completion: build_proto_completion(
            key: key,
            completed: 5,
            total: 15,
            percent: 33
          )
        )

        issue = TasklistBlocks::Issue.from_proto(issue: proto_issue)
        assert_equal "1-1-1-1", issue.uuid
        assert_equal 2, issue.issue_id
        assert_equal "My issue title", issue.title
        assert_equal "open", issue.state
        assert_equal "Some reason", issue.state_reason
        assert_equal "https://github.com/github/github/issues/1", issue.url
        assert_equal 4, issue.number
        assert_equal 3, issue.repository_id
        assert_equal "issues-graph", issue.repository_name
        assert_equal 1, issue.owner_id
        assert_equal "github", issue.owner_display_login
        assert_equal 1234, issue.position
        assert_equal 5, issue.completion.completed
        assert_equal 15, issue.completion.total
        assert_equal 33, issue.completion.percent
      end
    end

    context "from_tracking_block_proto" do
      test "initializes model from protobuf" do
        key = build_proto_key(
          owner_id: 1,
          item_id: 2,
          uuid: "1-1-1-1"
        )

        proto_issue = build_proto_issue(
          key: key,
          title: "My issue title",
          url: "https://github.com/github/github/issues/1",
          state: "open",
          state_reason: "Some reason",
          repo_name: "issues-graph",
          repo_id: 3,
          user_name: "github",
          number: 4,
          position: 1234,
          completion: build_proto_completion(
            key: key,
            completed: 5,
            total: 15,
            percent: 33
          )
        )

        proto_tracking_block = build_proto_tasklist_block(name: "My Tasks", issues: [proto_issue])

        issue = TasklistBlocks::Issue.from_tracking_block_proto(tracking_block: proto_tracking_block)
        assert_equal "1-1-1-1", issue.uuid
        assert_equal 2, issue.issue_id
        assert_equal "My issue title", issue.title
        assert_equal "open", issue.state
        assert_equal "Some reason", issue.state_reason
        assert_equal "https://github.com/github/github/issues/1", issue.url
        assert_equal 4, issue.number
        assert_equal 3, issue.repository_id
        assert_equal "issues-graph", issue.repository_name
        assert_equal 1, issue.owner_id
        assert_equal "github", issue.owner_display_login
        assert_equal 1234, issue.position
        assert_equal 5, issue.completion.completed
        assert_equal 15, issue.completion.total
        assert_equal 33, issue.completion.percent
        assert_equal "My Tasks", issue.tracked_by_title
      end
    end

    context "draft?" do
      test "is true when state is draft" do
        issue = TasklistBlocks::Issue.new(title: "My issue", state: TasklistBlocks::DraftIssueState::OPEN)
        assert_predicate issue, :draft?
      end

      test "is true when state is draftClosed" do
        issue = TasklistBlocks::Issue.new(title: "My issue", state: TasklistBlocks::DraftIssueState::CLOSED)
        assert_predicate issue, :draft?
      end

      test "is false when state is not draft or draftClosed" do
        issue = TasklistBlocks::Issue.new(title: "My issue", state: "open")
        refute_predicate issue, :draft?
      end
    end

    context "to_authorizable" do
      test "returns Issue::Authorizable when issue_id and repository_id are present" do
        issue = TasklistBlocks::Issue.new(title: "My issue", state: "open", issue_id: 1, repository_id: 2)
        authorizable = issue.to_authorizable

        assert_equal 1, authorizable.issue_id
        assert_equal 2, authorizable.repository_id
      end

      test "returns nil when issue_id is missing" do
        issue = TasklistBlocks::Issue.new(title: "My issue", state: "open", issue_id: nil, repository_id: 2)

        assert_nil issue.issue_id
        refute_nil issue.repository_id
        assert_nil issue.to_authorizable
      end

      test "returns nil when repository_id is missing" do
        issue = TasklistBlocks::Issue.new(title: "My issue", state: "open", issue_id: 1, repository_id: nil)

        refute_nil issue.issue_id
        assert_nil issue.repository_id
        assert_nil issue.to_authorizable
      end
    end

    test "to_h returns serialized issue" do
      issue = TasklistBlocks::Issue.new(
        uuid: "1-1-1-1",
        issue_id: 1,
        title: "My issue title",
        state: "open",
        state_reason: "Some reason",
        url: "https://github.com/github/github/issues/1",
        number: 1,
        repository_id: 2,
        repository_name: "github",
        owner_display_login: "github",
        position: 456,
        completion: TasklistBlocks::Completion.new(
          uuid: "1-1-1-1",
          completed: 5,
          total: 15,
          percent: 33
        )
      )
      expected_hash = {
        uuid: "1-1-1-1",
        item_id: 1,
        title: "My issue title",
        state: "open",
        state_reason: "Some reason",
        url: "https://github.com/github/github/issues/1",
        display_number: 1,
        repository_id: 2,
        repository_name: "github",
        owner_login: "github",
        position: 456,
        assignees: [],
        labels: [],
        title_html: nil,
        item_type: nil,
        tracked_by_title: nil,
        completion: {
          uuid: "1-1-1-1",
          completed: 5,
          total: 15,
          percent: 33
        }
      }

      assert_same_hash expected_hash, issue.to_h
    end

    test "to_h returns serialized issue with nil completion" do
      issue = TasklistBlocks::Issue.new(
        uuid: "1-1-1-1",
        issue_id: 1,
        title: "My issue title",
        state: "open",
        state_reason: "Some reason",
        url: "https://github.com/github/github/issues/1",
        number: 1,
        repository_id: 2,
        repository_name: "github",
        owner_display_login: "github",
        position: 456
      )
      expected_hash = {
        uuid: "1-1-1-1",
        item_id: 1,
        title: "My issue title",
        state: "open",
        state_reason: "Some reason",
        url: "https://github.com/github/github/issues/1",
        display_number: 1,
        repository_id: 2,
        repository_name: "github",
        owner_login: "github",
        position: 456,
        assignees: [],
        labels: [],
        title_html: nil,
        item_type: nil,
        tracked_by_title: nil,
        completion: nil,
      }

      assert_same_hash expected_hash, issue.to_h
    end

    context "#to_issue_link" do
      test "returns a hash with the shape the issue link class needs" do
        issue = TasklistBlocks::Issue.new(
          uuid: "1-1-1-1",
          issue_id: 1,
          title: "My issue title",
          state: "open",
          state_reason: "Some reason",
          url: "https://github.com/github/github/issues/1",
          number: 1,
          repository_id: 2,
          repository_name: "github",
          owner_display_login: "github",
          position: 456
        )
        expected = {
          issue_id: issue.issue_id,
          issue_number: issue.number,
          issue_state: issue.state,
          issue_state_reason: issue.state_reason,
          issue_title: issue.title,
          issue_url: issue.url,
          owner: issue.owner_display_login,
          repository: issue.repository_name,
        }
        assert_same_hash expected, issue.to_issue_link.serialize.symbolize_keys,
          "expected the issue to be converted to a hash with the correct shape"
      end
    end
  end
end
