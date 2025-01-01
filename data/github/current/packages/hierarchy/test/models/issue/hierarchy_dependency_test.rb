# typed: true
# frozen_string_literal: true
# fixed: true
require "test_helper"

class Issue::HierarchyDependencyTest < GitHub::TestCase
  include IssuesGraphTestHelpers
  include DogstatsTestHelpers

  test "#hierarchy allows callers to traverse the hierarchy" do
    issue = build(:issue)
    stubbed_tasklist_item = build_proto_issue
    stubbed_tasklist_block = build_proto_tasklist_block(issues: [stubbed_tasklist_item])
    mock_data = Struct
      .new(:tracking, :issue)
      .new([stubbed_tasklist_block], build_proto_issue)
    raw = mock_issues_graph_client.get_issue
    raw.stubs(:data).returns(mock_data)
    issue.hierarchy_raw = raw
    tasklist_block = issue.hierarchy.tasklist_blocks.first

    assert_equal stubbed_tasklist_block.name, tasklist_block.title
    assert_equal stubbed_tasklist_block.order, tasklist_block.order
    expected_item = TasklistBlocks::Issue.from_proto(issue: stubbed_tasklist_item)
    assert_equal expected_item, tasklist_block.items.first
  end

  test "#hierarchy returns an instance of Hierarchy populated with the raw response" do
    issue = build(:issue)
    raw = mock_issues_graph_client.get_issue
    issue.hierarchy_raw = raw
    assert_equal Hierarchy, issue.hierarchy.class
  end

  test "#hierarchy returns nil if the raw hierarchy is not preloaded" do
    assert_nil build(:issue).hierarchy
  end

  test "#hierarchy_loaded? indicates whether the raw hierarchy is set" do
    issue = build(:issue)
    raw = mock_issues_graph_client.get_issue

    refute issue.hierarchy_loaded?

    issue.hierarchy_raw = raw
    assert issue.hierarchy_loaded?
  end

  test "#hierarchy_raw returns the raw hierarchy if it is set" do
    issue = build(:issue)
    raw = mock_issues_graph_client.get_issue

    issue.hierarchy_raw = raw
    assert issue.hierarchy_raw
  end

  test "#hierarchy_raw returns nil if it is not set" do
    assert_nil build(:issue).hierarchy_raw
  end

  test "#hierarchy_raw=" do
    issue = build(:issue)
    raw = mock_issues_graph_client.get_issue

    issue.hierarchy_raw = raw
    assert issue.hierarchy_raw
  end

  context "ensure_valid_tasklist_blocks" do
    test "returns nil if the feature flag is disabled" do
      GitHub.flipper[:tasklist_block_input_validation].disable
      issue = build(:issue)

      assert_empty issue.errors
    end

    test "returns nil if there are no errors" do
      GitHub.flipper[:tasklist_block_input_validation].enable
      issue = build(:issue)
      issue.body_result.stubs(:tasklist_block_errors).returns([])
      issue.save!

      assert_empty issue.errors
    end

    test "returns nil if there are only limit errors" do
      GitHub.flipper[:tasklist_block_input_validation].enable
      GitHub.flipper[:tasklist_block_hard_limits].disable

      issue = build(:issue)
      issue.body_result.stubs(:tasklist_block_errors).returns([
        TasklistBlocks::LimitError.new(100, "tasklists"),
        TasklistBlocks::LimitError.new(50, "tasks"),
      ])
      issue.save!

      assert_empty issue.errors
    end

    test "adds to the ActiveRecord::Errors array if errors are found" do
      GitHub.flipper[:tasklist_block_input_validation].enable
      issue = build(:issue)
      issue.body_result.stubs(:tasklist_block_errors).returns([
        TasklistBlocks::ValidationError.new(0, 1, "invalid item"),
        TasklistBlocks::ValidationError.new(1, 3, "empty line"),
      ])

      begin
        issue.save!
      rescue ActiveRecord::RecordInvalid
        assert_equal 1, issue.errors[:tasklist_blocks].count
        assert_equal "contain the following errors -- invalid item at block 1, line 2; empty line at block 2, line 4", issue.errors[:tasklist_blocks].first
      end
    end
  end

  context "under_tasklist_blocks_limits" do
    test "returns nil if the feature flag is disabled" do
      GitHub.flipper[:tasklist_block_hard_limits].disable
      issue = build(:issue)

      assert_empty issue.errors
    end

    test "returns nil if there are no errors" do
      GitHub.flipper[:tasklist_block_hard_limits].enable
      issue = build(:issue)
      issue.body_result.stubs(:tasklist_block_errors).returns([])
      issue.save!

      assert_empty issue.errors
    end

    test "returns nil if there are only validation errors" do
      GitHub.flipper[:tasklist_block_hard_limits].enable
      GitHub.flipper[:tasklist_block_input_validation].disable

      issue = build(:issue)
      issue.body_result.stubs(:tasklist_block_errors).returns([
        TasklistBlocks::ValidationError.new(0, 1, "invalid item"),
        TasklistBlocks::ValidationError.new(1, 3, "empty line"),
      ])
      issue.save!

      assert_empty issue.errors
    end

    test "adds to the ActiveRecord::Errors array if errors are found" do
      GitHub.flipper[:tasklist_block_hard_limits].enable
      issue = build(:issue)
      issue.body_result.stubs(:tasklist_block_errors).returns([
        TasklistBlocks::LimitError.new(100, "tasklists"),
        TasklistBlocks::LimitError.new(50, "tasks"),
      ])

      begin
        issue.save!
      rescue ActiveRecord::RecordInvalid
        assert_equal 1, issue.errors[:tasklist_blocks].count
        assert_equal "Exceeded tasks limit, 50 items found", issue.errors[:tasklist_blocks].first
      end
    end
  end
end
