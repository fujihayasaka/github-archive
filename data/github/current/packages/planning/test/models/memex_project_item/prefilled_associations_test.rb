# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectItemPrefilledAssociationsTest < GitHub::TestCase
  include SubIssuesHelpers

  fixtures do
    @users = create_list(:user, 3)
    @labels = create_list(:label, 2)
    @repositories = create_list(:repository, 2)
    @milestones = create_list(:milestone, 2)
  end

  test "it allows access to the title column" do
    title_column = create(:memex_project_column, data_type: :title)
    prefilled_associations = MemexProjectItem::PrefilledAssociations.new(title_column: title_column)
    assert_equal prefilled_associations.title_column, title_column
  end

  test "it allows access to assignees" do
    # Reuse the draft/issue ids to ensure we handle collisions properly
    prefilled_associations = MemexProjectItem::PrefilledAssociations.new(
      draft_issue_ids_by_item_id: { 3 => 1, 4 => 2 },
      assignees_by_issue_id: {
        1 => [],
        2 => [@users[0], @users[1]],
      },
      assignees_by_draft_issue_id: {
        1 => [@users[1], @users[2]],
        2 => [],
      }
    )

    assert_equal [], prefilled_associations.assignees(MemexProjectItem.new(issue_id: 1))
    assert_equal [@users[0], @users[1]], prefilled_associations.assignees(MemexProjectItem.new(issue_id: 2))

    assert_equal [@users[1], @users[2]], prefilled_associations.assignees(MemexProjectItem.new(id: 3))
    assert_equal [], prefilled_associations.assignees(MemexProjectItem.new(id: 4))

    assert_equal [], prefilled_associations.assignees(MemexProjectItem.new(issue_id: 5))
    assert_nil prefilled_associations.assignees(MemexProjectItem.new(issue_id: 5), default_value: nil)
  end

  test "it allows access to labels" do
    prefilled_associations = MemexProjectItem::PrefilledAssociations.new(
      labels_by_issue_id: {
        1 => [],
        2 => @labels[0...1],
        3 => @labels
      }
    )

    assert_equal [], prefilled_associations.labels(MemexProjectItem.new(issue_id: 1))
    assert_equal @labels[0...1], prefilled_associations.labels(MemexProjectItem.new(issue_id: 2))
    assert_equal @labels, prefilled_associations.labels(MemexProjectItem.new(issue_id: 3))
    assert_equal [], prefilled_associations.labels(MemexProjectItem.new(issue_id: 4))
    assert_nil prefilled_associations.labels(MemexProjectItem.new(issue_id: 4), default_value: nil)
  end

  test "it allows access to repositories" do
    prefilled_associations = MemexProjectItem::PrefilledAssociations.new(
      repositories_by_issue_id: {
        1 => @repositories[0],
        2 => @repositories[1]
      }
    )

    assert_equal @repositories[0], prefilled_associations.repository(MemexProjectItem.new(issue_id: 1))
    assert_equal @repositories[1], prefilled_associations.repository(MemexProjectItem.new(issue_id: 2))
    assert_nil prefilled_associations.repository(MemexProjectItem.new(issue_id: 3))
  end

  test "it allows access to milestones" do
    prefilled_associations = MemexProjectItem::PrefilledAssociations.new(
      milestones_by_issue_id: {
        1 => @milestones[0],
        2 => @milestones[1]
      }
    )

    assert_equal @milestones[0], prefilled_associations.milestone(MemexProjectItem.new(issue_id: 1))
    assert_equal @milestones[1], prefilled_associations.milestone(MemexProjectItem.new(issue_id: 2))
    assert_nil prefilled_associations.milestone(MemexProjectItem.new(issue_id: 3))
  end

  test "it allows access to issue types" do
    feature_issue_type = IssueType.new(name: "Feature")
    bug_issue_type = IssueType.new(name: "Feature")
    prefilled_associations = MemexProjectItem::PrefilledAssociations.new(
      issue_types_by_issue_id: {
        1 => feature_issue_type,
        2 => bug_issue_type,
      }
    )

    assert_equal feature_issue_type, prefilled_associations.issue_type(MemexProjectItem.new(issue_id: 1))
    assert_equal bug_issue_type, prefilled_associations.issue_type(MemexProjectItem.new(issue_id: 2))
    assert_nil prefilled_associations.issue_type(MemexProjectItem.new(issue_id: 3))
  end

  test "it allows access to parent issue" do
    parent_issue_1 = create(:issue)
    parent_issue_2 = create(:issue)
    prefilled_associations = MemexProjectItem::PrefilledAssociations.new(
      parent_issues_by_issue_id: {
        1 => parent_issue_1,
        2 => parent_issue_2,
      }
    )

    assert_equal parent_issue_1, prefilled_associations.parent_issue(MemexProjectItem.new(issue_id: 1))
    assert_equal parent_issue_2, prefilled_associations.parent_issue(MemexProjectItem.new(issue_id: 2))
    assert_nil prefilled_associations.parent_issue(MemexProjectItem.new(issue_id: 3))
  end

  test "it allows access to sub issues progress" do
    issues = create_hierarchy! <<~HIERARCHY
    - parent
      - child1
      - child2
      - child3
    HIERARCHY

    parent = issues["parent"]

    sub_issue_list = parent&.recalculate_sub_issue_list!

    prefilled_associations = MemexProjectItem::PrefilledAssociations.new(
      sub_issues_progress_by_issue_id: {
        1 => sub_issue_list,
      }
    )

    assert_equal sub_issue_list, prefilled_associations.sub_issues_progress(MemexProjectItem.new(issue_id: 1))
    assert_nil prefilled_associations.sub_issues_progress(MemexProjectItem.new(issue_id: 3))
  end

  test "it allows access to tracked_by_items" do
    prefilled_associations = MemexProjectItem::PrefilledAssociations.new(
      tracked_by_items_by_issue_id: {
        1 => [],
      }
    )

    refute_nil prefilled_associations.tracked_by_items(MemexProjectItem.new(issue_id: 1))
  end

  context "partial failures" do
    test "it returns partial failures" do
      prefilled_associations = MemexProjectItem::PrefilledAssociations.new(
        partial_failures: [{
          memex_project_column: MemexProjectColumn::TRACKED_BY_COLUMN_NAME,
          message: "We encountered a problem retrieving the \"Tracked by\" data. Please try again later."
        }]
      )
      expected_partial_failures = [{
        memexProjectColumn: MemexProjectColumn::TRACKED_BY_COLUMN_NAME,
        message: "We encountered a problem retrieving the \"Tracked by\" data. Please try again later."
      }]

      assert_equal expected_partial_failures, prefilled_associations.partial_failures
    end

    test "it returns partial failures for a specific column" do
      prefilled_associations = MemexProjectItem::PrefilledAssociations.new(
        partial_failures: [
          {
            memex_project_column: MemexProjectColumn::TRACKED_BY_COLUMN_NAME,
            message: "We encountered a problem retrieving the \"Tracked by\" data. Please try again later."
          },
          {
            memex_project_column: MemexProjectColumn::TRACKS_COLUMN_NAME,
            message: "Error with tracks column"
          }
        ]
      )
      expected_partial_failures = {
        memexProjectColumn: MemexProjectColumn::TRACKED_BY_COLUMN_NAME,
        message: "We encountered a problem retrieving the \"Tracked by\" data. Please try again later."
      }

      assert_equal expected_partial_failures, prefilled_associations.partial_failures(MemexProjectColumn::TRACKED_BY_COLUMN_NAME)
    end
  end
end
