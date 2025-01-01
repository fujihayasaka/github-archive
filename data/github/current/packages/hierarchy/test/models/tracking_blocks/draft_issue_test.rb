# typed: true
# frozen_string_literal: true

require "test_helper"

module TrackingBlocks
  class TrackingBlocksDraftIssueTest < GitHub::TestCase
    test "equality" do
      issue = TrackingBlocks::DraftIssue.new(draft_issue: "Draft issue", owner_id: "owner_id", closed: true)
      other = TrackingBlocks::DraftIssue.new(draft_issue: "Draft issue", owner_id: "owner_id", closed: true)

      assert_equal issue, other
    end

    test "equality with different case" do
      issue = TrackingBlocks::DraftIssue.new(draft_issue: "Draft issue", owner_id: "owner_id")
      other = TrackingBlocks::DraftIssue.new(draft_issue: "draft issue", owner_id: "owner_id")

      refute_equal issue, other
    end

    test "equality with different owner_id" do
      issue = TrackingBlocks::DraftIssue.new(draft_issue: "Draft issue", owner_id: "owner_id")
      other = TrackingBlocks::DraftIssue.new(draft_issue: "draft issue", owner_id: "other_owner_id")

      refute_equal issue, other
    end

    test "equality with different uuid" do
      issue = TrackingBlocks::DraftIssue.new(draft_issue: "Draft issue", owner_id: "owner_id", uuid: "8-6-7")
      other = TrackingBlocks::DraftIssue.new(draft_issue: "Draft issue", owner_id: "owner_id", uuid: "5-3-0-9")

      refute_equal issue, other
    end

    test "equality with different state" do
      issue = TrackingBlocks::DraftIssue.new(draft_issue: "Draft issue", owner_id: "owner_id")
      other = TrackingBlocks::DraftIssue.new(draft_issue: "draft issue", owner_id: "owner_id", closed: true)

      refute_equal issue, other
    end

    test "to hierarchy model (open)" do
      issue = TrackingBlocks::DraftIssue.new(draft_issue: "Draft issue", owner_id: "owner_id", uuid: "1-9-8-4", position: 99)

      expected = {
        key: {
          ownerId: "owner_id",
          primaryKey: IssuesGraph::Proto::PrimaryKey.new(uuid: "1-9-8-4")
        },
        title: "Draft issue",
        state: TasklistBlocks::DraftIssueState::OPEN,
        position: 99,
        itemType: "DRAFT_ISSUE",
      }
      assert_equal expected, issue.to_hierarchy_model
    end

    test "to hierarchy model (closed)" do
      issue = TrackingBlocks::DraftIssue.new(draft_issue: "Draft issue", owner_id: "owner_id", uuid: "1-9-8-4", closed: true, position: 12)

      expected = {
        key: {
          ownerId: "owner_id",
          primaryKey: IssuesGraph::Proto::PrimaryKey.new(uuid: "1-9-8-4")
        },
        title: "Draft issue",
        state: TasklistBlocks::DraftIssueState::CLOSED,
        position: 12,
        itemType: "DRAFT_ISSUE",
      }
      assert_equal expected, issue.to_hierarchy_model
    end

    test "to tasklist issue (open)" do
      issue = TrackingBlocks::DraftIssue.new(draft_issue: "Draft issue", owner_id: 12, uuid: "1-9-8-4", position: 23)

      expected = TasklistBlocks::Issue.new(
        uuid: "1-9-8-4",
        title: "Draft issue",
        state: TasklistBlocks::DraftIssueState::OPEN,
        owner_id: 12,
        position: 23
      )
      assert_equal expected, issue.to_tasklist_issue
    end

    test "to tasklist issue (closed)" do
      issue = TrackingBlocks::DraftIssue.new(draft_issue: "Draft issue", owner_id: 12, uuid: "1-9-8-4", closed: true, position: 46)

      expected = TasklistBlocks::Issue.new(
        uuid: "1-9-8-4",
        title: "Draft issue",
        state: TasklistBlocks::DraftIssueState::CLOSED,
        owner_id: 12,
        position: 46
      )
      assert_equal expected, issue.to_tasklist_issue
    end

    test "#draft?" do
      assert_predicate TrackingBlocks::DraftIssue.new(draft_issue: "Draft issue", owner_id: 12), :draft?
    end
  end
end
