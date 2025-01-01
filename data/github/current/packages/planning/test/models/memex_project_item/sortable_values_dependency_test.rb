# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectItemSortableValuesDependencyTest < GitHub::TestCase
  include SubIssuesHelpers

  fixtures do
    @user = create(:verified_user)
    @org_admin = create(:verified_user)

    @org = create(:organization, login: "org", admin: @org_admin)
    @org.add_member(@user)

    enable_feature_flag(:sub_issues)
    enable_feature_flag(:issue_types, @org)

    @repo = create(:repository, owner: @org)
    @project = create(:memex_project, owner: @org)
    @issue = create(:issue, repository: @repo, user: @user)

    # Main target item to test sorting. All columns have a value assigned for this item.
    @item = create(
      :memex_project_item,
      :with_denormalized_title,
      :with_denormalized_milestone,
      memex_project: @project,
      content: @issue,
      creator: @user,
      priority_numerator: 4,
      priority_denominator: 4
    )

    @other_item = create(
      :memex_project_item,
      memex_project: @project,
      creator: @user,
      content: create(:draft_issue, title: "Draft Issue"),
      priority_numerator: 2,
      priority_denominator: 4
    )

    # Used to test sorting items with no column values. No values are assigned to this item.
    @valueless_item = create(
      :memex_project_item,
      memex_project: @project,
      creator: @user,
      content: create(:draft_issue, title: "Draft Issue"),
      priority_numerator: 3,
      priority_denominator: 4
    )

    # Mainly hiding a lot more test setup in this method.
    # Scenario values are assigned to the columns in this method..
    setup_all_columns!
  end

  setup do
    # Makes testing easier, these values are private constants in the module.
    @max_int = 9223372036854775807
    @min_int = -9223372036854775808

    @date_timestamp = (@date_value.to_time(:utc).to_f * 1000).to_i
    @iteration_timestamp = (@iteration_options[0]["start_date"].to_time(:utc).to_f * 1000).to_i

    # rubocop:disable Layout/SpaceInsideArrayLiteralBrackets
    @scenarios = [
      # Column                       Present value          Missing ascending Missing descending
      [ @assignees_column,           @user.login,           nil,              nil               ],
      [ @date_column,                @date_timestamp,       @max_int,         @min_int          ],
      [ @issue_type_column,          @issue_type.name,      nil,              nil               ],
      [ @iteration_column,           @iteration_timestamp,  @max_int,         @min_int          ],
      [ @labels_column,              @label.name,           nil,              nil               ],
      [ @linked_pulls_column,        nil,                   nil,              nil               ],
      [ @milestone_column,           @milestone.title,      nil,              nil               ],
      [ @number_column,              1.1.to_d,              Float::INFINITY,  -Float::INFINITY  ],
      [ @parent_issue_column,        @parent_issue.title,   nil,              nil               ],
      [ @single_select_column,       0.0,                   1000.0,           -1000.0           ],
      [ @status_column,              0.0,                   1000.0,           -1000.0           ],
      [ @sub_issues_progress_column, "66",                  nil,              nil               ],
      [ @text_column,                "Sample text A",       nil,              nil               ],
      [ @title_column,               @issue.title,          nil,              nil               ],
      [ @tracked_by_column,          nil,                   nil,              nil               ],
      [ @tracks_column,              nil,                   nil,              nil               ],
    ]
    # rubocop:enable Layout/SpaceInsideArrayLiteralBrackets

    @columns = @scenarios.transpose[0]
    @present_values = @scenarios.transpose[1]
    @missing_ascending_values  = @scenarios.transpose[2]
    @missing_descending_values = @scenarios.transpose[3]

    @sort_by_desc = @columns.map { |column| { column:, direction: :desc } }
    @sort_by_asc  = @columns.map { |column| { column:, direction: :asc } }

    @prefilled_associations = MemexProjectItemPrefiller.new(
      [@item, @other_item, @valueless_item],
      columns: @columns,
      read_denormalized_title: true,
      title_column: @title_column,
      read_denormalized_milestone: true
    ).prefill
  end

  context ".sort_by_sortable_values" do
    test "supports sorting multiple columns in different directions" do
      # Sorting by number ascending
      assert_sorted_items [@item, @other_item, @valueless_item],
        sort_by: [{ column: @number_column, direction: :asc }]

      # Sorting by number descending
      assert_sorted_items [@other_item, @item, @valueless_item],
        sort_by: [{ column: @number_column, direction: :desc }]

      # Sorting by date ascending and text ascending.
      # item and other_item have the same date value so the text column is used for sorting.
      assert_sorted_items [@item, @other_item, @valueless_item],
        sort_by: [
          { column: @date_column, direction: :asc },
          { column: @text_column, direction: :asc },
        ]

      # Sorting by date ascending and text descending
      assert_sorted_items [@other_item, @item, @valueless_item],
        sort_by: [
          { column: @date_column, direction: :asc },
          { column: @text_column, direction: :desc },
        ]
    end

    test "with no sorting, sorts by priority desc and ID asc" do
      # Sorting by virtual priority descending
      assert_sorted_items [@item, @valueless_item, @other_item], sort_by: []

      @item.update!(priority_numerator: nil, priority_denominator: nil)
      @other_item.update!(priority_numerator: nil, priority_denominator: nil)
      @valueless_item.update!(priority_numerator: nil, priority_denominator: nil)

      @item.reload
      @other_item.reload
      @valueless_item.reload

      # All priorities are nil, so sorting is now by ID ascending
      assert_sorted_items [@item, @other_item, @valueless_item], sort_by: []
    end
  end

  context ".compare_sortable_value" do
    test "returns 0 when both values are nil in either order" do
      assert_equal 0, MemexProjectItem::SortableValuesDependency.compare_sortable_value(nil, nil, :asc)
      assert_equal 0, MemexProjectItem::SortableValuesDependency.compare_sortable_value(nil, nil, :desc)
    end

    test "returns 1 when left value is nil in either order" do
      assert_equal 1, MemexProjectItem::SortableValuesDependency.compare_sortable_value(nil, 1, :asc)
      assert_equal 1, MemexProjectItem::SortableValuesDependency.compare_sortable_value(nil, 1, :desc)
    end

    test "returns -1 when right value is nil in either order" do
      assert_equal -1, MemexProjectItem::SortableValuesDependency.compare_sortable_value(1, nil, :asc)
      assert_equal -1, MemexProjectItem::SortableValuesDependency.compare_sortable_value(1, nil, :desc)
    end

    test "returns 0 when both values are equal in either order" do
      assert_equal 0, MemexProjectItem::SortableValuesDependency.compare_sortable_value(1, 1, :asc)
      assert_equal 0, MemexProjectItem::SortableValuesDependency.compare_sortable_value(1, 1, :desc)
    end

    test "returns -1 when left value is less than right value in ascending order" do
      assert_equal -1, MemexProjectItem::SortableValuesDependency.compare_sortable_value(1, 2, :asc)
    end

    test "returns 1 when left value is less than right value in descending order" do
      assert_equal 1, MemexProjectItem::SortableValuesDependency.compare_sortable_value(1, 2, :desc)
    end

    test "returns 1 when left value is greater than right value in ascending order" do
      assert_equal 1, MemexProjectItem::SortableValuesDependency.compare_sortable_value(2, 1, :asc)
    end

    test "returns -1 when left value is greater than right value in descending order" do
      assert_equal -1, MemexProjectItem::SortableValuesDependency.compare_sortable_value(2, 1, :desc)
    end
  end

  context "#derive_sortable_values" do
    test "returns correct values when ascending and descending" do
      assert_equal [*@present_values, @item.virtual_priority.to_d, @item.id],
        @item.derive_sortable_values(sort_by: @sort_by_desc, prefilled_associations: @prefilled_associations)

      assert_equal [*@present_values, @item.virtual_priority.to_d, @item.id],
        @item.derive_sortable_values(sort_by: @sort_by_asc, prefilled_associations: @prefilled_associations)
    end

    test "returns correct values for columns that have no data when descending" do
      assert_equal [*@missing_ascending_values, @valueless_item.virtual_priority.to_d, @valueless_item.id],
        @valueless_item.derive_sortable_values(sort_by: @sort_by_asc, prefilled_associations: @prefilled_associations)
    end

    test "returns correct values for columns that have no data when ascending" do
      assert_equal [*@missing_descending_values, @valueless_item.virtual_priority.to_d, @valueless_item.id],
        @valueless_item.derive_sortable_values(sort_by: @sort_by_desc, prefilled_associations: @prefilled_associations)
    end
  end

  def assert_sorted_items(expected_items, sort_by:)
    unsorted_items = [@item, @valueless_item, @other_item]

    sorted_items = MemexProjectItem::SortableValuesDependency.sort_by_sortable_values(
      unsorted_items,
      sort_by:,
      prefilled_associations: @prefilled_associations,
    )

    assert_equal expected_items.pluck(:id), sorted_items.pluck(:id), <<~MSG
      Expected items to be sorted by #{sort_by.map { |s| "#{s[:column].data_type} #{s[:direction]}" }.join(", ")}"
      Sorting values: #{sorted_items.map(&:sort_values).inspect}
    MSG
  end

  # Called in tests to setup all columns and assign values to them.
  def setup_all_columns!
    # Assignees
    @assignees_column = @project.find_column_by_name_or_id(MemexProjectColumn::ASSIGNEES_COLUMN_NAME)
    @item.set_column_value(@assignees_column, [@user.id], @user)

    # Date
    @date_column = create(:date_memex_column, memex_project: @project, creator: @user)
    @date_value = Date.new(2024, 10, 8).freeze
    @item.set_column_value(@date_column, @date_value.to_s, @user)
    @other_item.set_column_value(@date_column, @date_value.to_s, @user)

    # Issue Type
    @issue_type_column = @project.find_column_by_name_or_id(MemexProjectColumn::TYPE_COLUMN_NAME)
    @issue_type = create(:issue_type, owner: @org, name: "test_issue_type")
    @item.set_column_value(@issue_type_column, @issue_type.id, @org_admin)

    # Iteration
    @iteration_column = create(:iteration_memex_column, memex_project: @project, creator: @user)
    @iteration_options = @iteration_column.settings.dig("configuration", "iterations")
    @item.set_column_value(@iteration_column, @iteration_options[0]["id"], @user)

    # Labels
    @labels_column = @project.find_column_by_name_or_id(MemexProjectColumn::LABELS_COLUMN_NAME)
    @label = create(:label, repository: @repo)
    @item.set_column_value(@labels_column, [@label.id], @user)

    # Linked Pull Requests
    @linked_pulls_column = @project.find_column_by_name_or_id(MemexProjectColumn::LINKED_PULL_REQUESTS_COLUMN_NAME)
    @pull_request = create(:pull_request, :disable_disk_access, repository: @repo, user: @user)
    @item.set_column_value(@linked_pulls_column, [@pull_request.id], @user)

    # Milestone
    @milestone_column = @project.find_column_by_name_or_id(MemexProjectColumn::MILESTONE_COLUMN_NAME)
    @milestone = create(:milestone, repository: @repo)
    @item.set_column_value(@milestone_column, @milestone.id, @user)

    # Number
    @number_column = create(:number_memex_column, memex_project: @project, creator: @user)
    @item.set_column_value(@number_column, 1.1, @user)
    @other_item.set_column_value(@number_column, 1.5, @user)

    # Parent Issue
    @parent_issue_column = @project.find_column_by_name_or_id(MemexProjectColumn::PARENT_ISSUE_COLUMN_NAME)
    @parent_issue = create(:issue, repository: @repo, user: @user)
    @item.set_column_value(@parent_issue_column, @parent_issue.id, @user)

    # Repository
    @repository_column = @project.find_column_by_name_or_id(MemexProjectColumn::REPOSITORY_COLUMN_NAME)
    @item.set_column_value(@repository_column, @repo.id, @user)

    # Reviewers
    @reviewers_column = create(:memex_project_column, memex_project: @project, data_type: "reviewers", user_defined: false, creator: @user)
    @item.set_column_value(@reviewers_column, [@user.id], @user)

    # Single Select
    @single_select_column = create(:single_select_memex_column, memex_project: @project, creator: @user)
    @single_select_options = @single_select_column.settings["options"]
    @item.set_column_value(@single_select_column, @single_select_options[0]["id"], @user)

    # Status
    @status_column = @project.find_column_by_name_or_id(MemexProjectColumn::STATUS_COLUMN_NAME)
    @status_options = @status_column.settings["options"]
    @item.set_column_value(@status_column, @status_options[0]["id"], @user)

    # Sub Issues Progress
    @sub_issues_progress_column = @project.find_column_by_name_or_id(MemexProjectColumn::SUB_ISSUES_PROGRESS_COLUMN_NAME)

    child1 = create(:issue, repository: @repo, user: @user)
    child2 = create(:issue, repository: @repo, user: @user)
    child3 = create(:issue, repository: @repo, user: @user)

    hierarchy = <<~HIERARCHY
    - #{@issue}
      - #{child1}
      - #{child2}
      - #{child3}
    HIERARCHY

    create_hierarchy!(hierarchy, issues: [@issue, child1, child2, child3])
    child1.close!
    child2.close!

    @issue.recalculate_sub_issue_list!

    # Text
    @text_column = create(:memex_project_column, memex_project: @project, user_defined: true, creator: @user)
    @item.set_column_value(@text_column, "Sample text A", @user)
    @other_item.set_column_value(@text_column, "Sample text B", @user)

    # Title
    @title_column = @project.find_column_by_name_or_id(MemexProjectColumn::TITLE_COLUMN_NAME)

    # Tracked By
    @tracked_by_column = @project.find_column_by_name_or_id(MemexProjectColumn::TRACKED_BY_COLUMN_NAME)
    @tracked_by_issue = create(:issue, repository: @repo, user: @user)
    @item.set_column_value(@tracked_by_column, [@tracked_by_issue.id], @user)

    # Tracks
    @tracks_column = @project.find_column_by_name_or_id(MemexProjectColumn::TRACKS_COLUMN_NAME)
    @tracks_issue = create(:issue, repository: @repo, user: @user)
    @item.set_column_value(@tracks_column, [@tracks_issue.id], @user)
  end
end
