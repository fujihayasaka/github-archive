# typed: true
# frozen_string_literal: true

require "test_helper"

# Tests for Search::Queries::MemexProjectItemQuery.insights_query
# These cover querying for current state and historical Insights chart data.
class SearchQueriesMemexProjectItemQueryInsightsTest < GitHub::TestCase
  include MemexHelpers

  MISSING_VALUE_GROUP_KEY = MemexProjectColumn::Interface::Groupable::MISSING_VALUE_GROUP_KEY
  Chartable = MemexProjectColumn::Interface::Chartable

  fixtures do
    @time = Time.now.utc.freeze
    @user = create(:verified_user, login: "project-admin")
    @memex = create(:memex_project, owner: @user)
    @repo = create(:repository, owner: @user, name: "app")

    # Current state chart tests
    @status_column = @memex.status_column
    @assignee_column = @memex.columns.find(&:assignees?)
    @estimate_column = create(:number_memex_column, memex_project: @memex, name: "Estimate")
    @actual_column = create(:number_memex_column, memex_project: @memex, name: "Actual Effort")
    @current_state_items = create_current_state_test_items

    # Historical chart tests
    items = create_historical_test_items(time: @time, repo: @repo, memex: @memex, add_y_agg_values: true)
    @historical_items = items[:issue_items] + items[:pr_items] + items[:draft_items]
  end

  setup do
    setup_search
  end

  teardown_once do
    teardown_search
  end

  # The current state test items are as follows:

  # +---------+--------------+-------------+---------------+---------------+
  # | Item i  |    Status    |  Assignees  |   Estimate    |    Actual     |
  # +---------+--------------+-------------+---------------+---------------+
  # | Item 0  |              |             |      5        |               |
  # +---------+--------------+-------------+---------------+---------------+
  # | Item 1  |     Done     |     Ren     |      5        |       99.5    |
  # +---------+--------------+-------------+---------------+---------------+
  # | Item 2  | In Progress  |     Ren     |      5.006    |      200      |
  # +---------+--------------+-------------+---------------+---------------+
  # | Item 3  |     Done     | Ren,Stimpy  |      5        |      500.75   |
  # +---------+--------------+-------------+---------------+---------------+
  # | Item 4  |              |     Ren     |      5        |       50      |
  # +---------+--------------+-------------+---------------+---------------+
  # | Item 5  |              |     Ren     |      5        |        0      |
  # +---------+--------------+-------------+---------------+---------------+
  # | Item 6  | In Progress  |             |      5        |      400      |
  # +---------+--------------+-------------+---------------+---------------+
  # | Item 7  | In Progress  |   Stimpy    |      5        |     1000      |
  # +---------+--------------+-------------+---------------+---------------+
  # | Item 8  | In Progress  |   Stimpy    |      5        |      700      |
  # +---------+--------------+-------------+---------------+---------------+
  # | Item 9  | In Progress  |   Stimpy    |      5        |               |
  # +---------+--------------+-------------+---------------+---------------+
  sig { returns(T::Array[MemexProjectItem]) }
  private def create_current_state_test_items
    item_count = 10
    user_ren = create(:verified_user, login: "ren")
    user_stimpy = create(:verified_user, login: "stimpy")
    user_george = create(:verified_user, login: "george")
    @repo.add_member(user_ren)
    @repo.add_member(user_stimpy)
    @repo.add_member(user_george)

    status_options = @status_column.settings["options"]
    todo = status_options.find { |o| o["name"] == "Todo" }["id"]
    done = status_options.find { |o| o["name"] == "Done" }["id"]
    in_progress = status_options.find { |o| o["name"] == "In Progress" }["id"]
    ren_n_stimpy = [user_ren.id, user_stimpy.id]
    items = item_count.times.map do
      create(:memex_project_item, content: create(:issue, repository: @repo), memex_project: @memex)
    end
    set_column_values(items[0],                                                                    [[@estimate_column, 5]])
    set_column_values(items[1], [[@status_column, done],        [@assignee_column, user_ren.id],    [@estimate_column, 5], [@actual_column, 99.5]])
    set_column_values(items[2], [[@status_column, in_progress], [@assignee_column, user_ren.id],    [@estimate_column, 5.006], [@actual_column, 200]])
    set_column_values(items[3], [[@status_column, done],        [@assignee_column, ren_n_stimpy],   [@estimate_column, 5], [@actual_column, 500.75]])
    set_column_values(items[4],                                [[@assignee_column, user_ren.id],    [@estimate_column, 5], [@actual_column, 50]])
    set_column_values(items[5],                                [[@assignee_column, user_ren.id],    [@estimate_column, 5], [@actual_column, 0]])
    set_column_values(items[6], [[@status_column, in_progress],                                     [@estimate_column, 5], [@actual_column, 400]])
    set_column_values(items[7], [[@status_column, in_progress], [@assignee_column, user_stimpy.id], [@estimate_column, 5], [@actual_column, 1000]])
    set_column_values(items[8], [[@status_column, in_progress], [@assignee_column, user_stimpy.id], [@estimate_column, 5], [@actual_column, 700]])
    set_column_values(items[9], [[@status_column, in_progress], [@assignee_column, user_stimpy.id], [@estimate_column, 5]])
    items
  end

  # The historicial test items are as follows:

  # +---------+--------------+-------------+-------------+-------------+---------------+---------------+
  # | Item i  |      Type    |   Created   |   Closed    |   Reason    |   Estimate    |    Actual     |
  # +---------+--------------+-------------+-------------+-------------+---------------+---------------+
  # | Item 0  |    issue     | 4.days.ago  |             |             |      5        |               |
  # +---------+--------------+-------------+-------------+-------------+---------------+---------------+
  # | Item 1  |    issue     | 6.days.ago  | 2.days.ago  |             |      5        |       99.5    |
  # +---------+--------------+-------------+-------------+-------------+---------------+---------------+
  # | Item 2  |    issue     | 8.days.ago  | 2.days.ago  |             |      5.006    |      200      |
  # +---------+--------------+-------------+-------------+-------------+---------------+---------------+
  # | Item 3  |    issue     | 8.days.ago  | 4.days.ago  | not_planned |      5        |      500.75   |
  # +---------+--------------+-------------+-------------+-------------+---------------+---------------+
  # | Item 4  |    issue     | 6.days.ago  | 2.days.ago  | duplicate   |      5        |       50      |
  # +---------+--------------+-------------+-------------+-------------+---------------+---------------+
  # | Item 5  |    issue     | 8.days.ago  | 4.days.ago  | duplicate   |      5        |        0      |
  # +---------+--------------+-------------+-------------+-------------+---------------+---------------+
  # | Item 6  |    pr        | 4.days.ago  |             |             |      5        |      400      |
  # +---------+--------------+-------------+-------------+-------------+---------------+---------------+
  # | Item 7  |    pr        | 6.days.ago  | 4.days.ago  |  closed     |      5        |     1000      |
  # +---------+--------------+-------------+-------------+-------------+---------------+---------------+
  # | Item 8  |    pr        | 8.days.ago  | 3.days.ago  |  merged     |      5        |      700      |
  # +---------+--------------+-------------+-------------+-------------+---------------+---------------+
  # | Item 9  |    pr        | 10.days.ago | 2.days.ago  |  merged     |      5        |               |
  # +---------+--------------+-------------+-------------+-------------+---------------+---------------+
  # | Item 10 |    draft     | 6.days.ago  | 4.days.ago  |             |      5        |       80      |
  # +---------+--------------+-------------+-------------+-------------+---------------+---------------+
  # | Item 11 |    draft     | 8.days.ago  | 4.days.ago  |             |      5        |      150      |
  # +---------+--------------+-------------+-------------+-------------+---------------+---------------+
  sig do params(time: Time, repo: Repository, memex: MemexProject, add_y_agg_values: T::Boolean).returns({
    issue_items: T::Array[MemexProjectItem],
    pr_items: T::Array[MemexProjectItem],
    draft_items: T::Array[MemexProjectItem],
  })
  end
  private def create_historical_test_items(time:, repo:, memex:, add_y_agg_values: false)
    item_arrays = T.let({ issue_items: [], pr_items: [], draft_items: [] }, { issue_items: T::Array[MemexProjectItem], pr_items: T::Array[MemexProjectItem], draft_items: T::Array[MemexProjectItem] })
    Timecop.freeze(time) do
      issues = [
        create(:issue, repository: repo, created_at: 4.days.ago),
        create(:issue, repository: repo, created_at: 6.days.ago, state: :closed, closed_at: 2.days.ago),
        create(:issue, repository: repo, created_at: 8.days.ago, state: :closed, closed_at: 2.days.ago),
        create(:issue, repository: repo, created_at: 8.days.ago, state: :closed, closed_at: 4.days.ago, state_reason: :not_planned),
        create(:issue, repository: repo, created_at: 6.days.ago, state: :closed, closed_at: 2.days.ago, state_reason: :duplicate),
        create(:issue, repository: repo, created_at: 8.days.ago, state: :closed, closed_at: 4.days.ago, state_reason: :duplicate),
      ]

      prs = [
        create(:pull_request, :disable_disk_access, created_at: 4.days.ago),
        create(:pull_request, :disable_disk_access, :closed, created_at: 6.days.ago),
        create(:pull_request, :disable_disk_access, :merged, created_at: 8.days.ago, merged_at: 3.days.ago),
        create(:pull_request, :disable_disk_access, :merged, created_at: 10.days.ago, merged_at: 2.days.ago)
      ]
      prs[1].issue.update!(closed_at: 4.days.ago)
      prs[2].issue.update!(closed_at: 3.days.ago)
      prs[3].issue.update!(closed_at: 2.days.ago)

      draft_issues = [
        create(:draft_issue, created_at: 6.days.ago),
        create(:draft_issue, created_at: 8.days.ago),
      ]

      issue_items = issues.map { |issue| create(:memex_project_item, content: issue, memex_project: memex) }
      pr_items = prs.map { |pr| create(:memex_project_item, content: pr, memex_project: memex) }
      draft_items = draft_issues.map { |draft| create(:memex_project_item, content: draft, memex_project: memex) }
      item_arrays = { issue_items:, pr_items:, draft_items: }
    end

    if add_y_agg_values
      items = item_arrays[:issue_items] + item_arrays[:pr_items] + item_arrays[:draft_items]
      set_column_values(items[0],  [[@estimate_column, 5]])
      set_column_values(items[1],  [[@estimate_column, 5], [@actual_column, 99.5]])
      set_column_values(items[2],  [[@estimate_column, 5.006], [@actual_column, 200]])
      set_column_values(items[3],  [[@estimate_column, 5], [@actual_column, 500.75]])
      set_column_values(items[4],  [[@estimate_column, 5], [@actual_column, 50]])
      set_column_values(items[5],  [[@estimate_column, 5], [@actual_column, 0]])
      set_column_values(items[6],  [[@estimate_column, 5], [@actual_column, 400]])
      set_column_values(items[7],  [[@estimate_column, 5], [@actual_column, 1000]])
      set_column_values(items[8],  [[@estimate_column, 5], [@actual_column, 700]])
      set_column_values(items[9],  [[@estimate_column, 5]])
      set_column_values(items[10], [[@estimate_column, 5], [@actual_column, 80]])
      set_column_values(items[11], [[@estimate_column, 5], [@actual_column, 150]])
    end
    item_arrays
  end

  context "current state charts" do
    test "returns grouped chart data for Status grouped by Assignee" do
      item_count = @current_state_items.count
      populate_elasticsearch_index!(@current_state_items)

      chart_options = Chartable::Options.new(
        x_axis: Chartable::Options::XAxis.new(
          data_source: Chartable::Options::XAxisDataSource.new(
            field_object_or_id: @status_column.id,
          ),
          group_by: Chartable::Options::XAxisGroupBy.new(
            field_object_or_id: @assignee_column.id,
          )
        )
      )

      query = Search::Queries::MemexProjectItemQuery.insights_query(
        project: @memex,
        viewer: @user,
        chart_options: chart_options,
      )
      response = T.cast(query.execute, Search::Responses::MemexProjectItemResponse)

      assert_equal item_count, response.chart_data&.total_count, "Insights query results did not match the expected number of documents"

      # sanity check that we have 4 Status options: Todo, In Progress, Done, and nil.
      options_and_no_value_count = @status_column.settings["options"].count + 1 # +1 for _noValue
      assert_equal 4, options_and_no_value_count

      # assert we have the expected x_axis values
      # Note that 'Todo' is not included because no items have that value.
      # Also note that 'In Progress' is correctly ordered before 'Done', with missing last.
      expected_sorted_x_values = ["In Progress", "Done", MISSING_VALUE_GROUP_KEY]
      assert_equal expected_sorted_x_values, response.chart_data&.x_axis&.values

      # assert that we have the expected grouped assignee values
      expected_sorted_group_values = ["ren", "stimpy", MISSING_VALUE_GROUP_KEY]
      assert_equal expected_sorted_group_values, response.chart_data&.data_series&.map(&:name)

      # assert that we have the expected group data counts for each x_axis value
      # note that one Done item is counted twice since it is assigned to both ren and stimpy
      expected_sorted_group_counts = [
        [1, 2, 2], # ren [In Progress, Done, missing]
        [3, 1, 0], # stimpy [In Progress, Done, missing]
        [1, 0, 1], # missing [In Progress, Done, missing]
      ]
      assert_equal expected_sorted_group_counts, response.chart_data&.data_series&.map(&:data)
    end

    test "returns chart data for Status taking the SUM over an Estimate field" do
      item_count = @current_state_items.count
      populate_elasticsearch_index!(@current_state_items)

      chart_options = Chartable::Options.new(
        x_axis: Chartable::Options::XAxis.new(
          data_source: Chartable::Options::XAxisDataSource.new(
            field_object_or_id: @status_column.id,
          )
        ),
        y_axis: Chartable::Options::YAxis.new(
          aggregate: Chartable::Options::YAxisAggregate.new(
            operation: MemexProjectChart::Operation::Sum,
            field_object_or_id: @estimate_column.id
          )
        )
      )

      query = Search::Queries::MemexProjectItemQuery.insights_query(
        project: @memex,
        viewer: @user,
        chart_options: chart_options,
      )
      response = T.cast(query.execute, Search::Responses::MemexProjectItemResponse)

      assert_equal item_count, response.chart_data&.total_count, "Insights query results did not match the expected number of documents"

      # sanity check that we have 4 Status options: Todo, In Progress, Done, and nil.
      options_and_no_value_count = @status_column.settings["options"].count + 1 # +1 for _noValue
      assert_equal 4, options_and_no_value_count

      # assert we have the expected x_axis values
      # Note that 'Todo' is not included because no items have that value.
      # Also note that 'In Progress' is correctly ordered before 'Done', with missing last.
      expected_sorted_x_values = ["In Progress", "Done", MISSING_VALUE_GROUP_KEY]
      assert_equal expected_sorted_x_values, response.chart_data&.x_axis&.values

      # Since we're not grouping, we just have the one anonymous data series
      expected_data_series = [""]
      assert_equal expected_data_series, response.chart_data&.data_series&.map(&:name)

      # Since we're not grouping, we just have the one data series for summed estimates (as floats, rounded to 2 decimal places)
      expected_sorted_group_sums = [
        [25.01, 10.0, 15.0], # total [In Progress, Done, missing]
      ]

      assert_equal expected_sorted_group_sums, response.chart_data&.data_series&.map(&:data)
    end

    test "returns grouped chart data for Status grouped by Assignee, taking the SUM over an Estimate field" do
      item_count = @current_state_items.count
      populate_elasticsearch_index!(@current_state_items)

      chart_options = Chartable::Options.new(
        x_axis: Chartable::Options::XAxis.new(
          data_source: Chartable::Options::XAxisDataSource.new(
            field_object_or_id: @status_column.id,
          ),
          group_by: Chartable::Options::XAxisGroupBy.new(
            field_object_or_id: @assignee_column.id,
          )
        ),
        y_axis: Chartable::Options::YAxis.new(
          aggregate: Chartable::Options::YAxisAggregate.new(
            operation: MemexProjectChart::Operation::Sum,
            field_object_or_id: @estimate_column.id
          )
        )
      )

      query = Search::Queries::MemexProjectItemQuery.insights_query(
        project: @memex,
        viewer: @user,
        chart_options: chart_options,
      )
      response = T.cast(query.execute, Search::Responses::MemexProjectItemResponse)

      assert_equal item_count, response.chart_data&.total_count, "Insights query results did not match the expected number of documents"

      # sanity check that we have 4 Status options: Todo, In Progress, Done, and nil.
      options_and_no_value_count = @status_column.settings["options"].count + 1 # +1 for _noValue
      assert_equal 4, options_and_no_value_count

      # assert we have the expected x_axis values
      # Note that 'Todo' is not included because no items have that value.
      # Also note that 'In Progress' is correctly ordered before 'Done', with missing last.
      expected_sorted_x_values = ["In Progress", "Done", MISSING_VALUE_GROUP_KEY]
      assert_equal expected_sorted_x_values, response.chart_data&.x_axis&.values

      # assert that we have the expected grouped assignee values
      expected_sorted_group_values = ["ren", "stimpy", MISSING_VALUE_GROUP_KEY]
      assert_equal expected_sorted_group_values, response.chart_data&.data_series&.map(&:name)

      # assert that we have the expected group data (sum of estimates) for each x_axis value (as floats, rounded to 2 decimal places)
      # note that one Done item is counted twice since it is assigned to both ren and stimpy
      expected_sorted_group_sums = [
        [5.01, 10.0, 10.0], # ren [In Progress, Done, missing]
        [15.0, 5.0,  0.0], # stimpy [In Progress, Done, missing]
        [5.0,  0.0,  5.0], # missing [In Progress, Done, missing]
      ]
      assert_equal expected_sorted_group_sums, response.chart_data&.data_series&.map(&:data)
    end

    test "returns chart data for Status taking the MIN over an Actual field" do
      item_count = @current_state_items.count
      populate_elasticsearch_index!(@current_state_items)

      chart_options = Chartable::Options.new(
        x_axis: Chartable::Options::XAxis.new(
          data_source: Chartable::Options::XAxisDataSource.new(
            field_object_or_id: @status_column.to_field,
          )
        ),
        y_axis: Chartable::Options::YAxis.new(
          aggregate: Chartable::Options::YAxisAggregate.new(
            operation: MemexProjectChart::Operation::Min,
            field_object_or_id: @actual_column.to_field,
          )
        )
      )

      query = Search::Queries::MemexProjectItemQuery.insights_query(
        project: @memex,
        viewer: @user,
        chart_options: chart_options,
      )
      response = T.cast(query.execute, Search::Responses::MemexProjectItemResponse)

      assert_equal item_count, response.chart_data&.total_count, "Insights query results did not match the expected number of documents"

      # sanity check that we have 4 Status options: Todo, In Progress, Done, and nil.
      options_and_no_value_count = @status_column.settings["options"].count + 1 # +1 for _noValue
      assert_equal 4, options_and_no_value_count

      # assert we have the expected x_axis values
      # Note that 'Todo' is not included because no items have that value.
      # Also note that 'In Progress' is correctly ordered before 'Done', with missing last.
      expected_sorted_x_values = ["In Progress", "Done", MISSING_VALUE_GROUP_KEY]
      assert_equal expected_sorted_x_values, response.chart_data&.x_axis&.values

      # Since we're not grouping, we just have the one anonymous data series
      expected_data_series = [""]
      assert_equal expected_data_series, response.chart_data&.data_series&.map(&:name)

      # Since we're not grouping, we just have the one data series for min Actual (as floats)
      expected_sorted_group_mins = [
        [200, 99.5, 0], # total [In Progress, Done, missing]
      ]

      assert_equal expected_sorted_group_mins, response.chart_data&.data_series&.map(&:data)
    end

    test "returns grouped chart data for Status grouped by Assignee, taking the MIN over an Actual field" do
      item_count = @current_state_items.count
      populate_elasticsearch_index!(@current_state_items)

      chart_options = Chartable::Options.new(
        x_axis: Chartable::Options::XAxis.new(
          data_source: Chartable::Options::XAxisDataSource.new(
            field_object_or_id: @status_column.to_field,
          ),
          group_by: Chartable::Options::XAxisGroupBy.new(
            field_object_or_id: @assignee_column.to_field,
          )
        ),
        y_axis: Chartable::Options::YAxis.new(
          aggregate: Chartable::Options::YAxisAggregate.new(
            operation: MemexProjectChart::Operation::Min,
            field_object_or_id: @actual_column.to_field,
          )
        )
      )

      query = Search::Queries::MemexProjectItemQuery.insights_query(
        project: @memex,
        viewer: @user,
        chart_options: chart_options,
      )
      response = T.cast(query.execute, Search::Responses::MemexProjectItemResponse)

      assert_equal item_count, response.chart_data&.total_count, "Insights query results did not match the expected number of documents"

      # sanity check that we have 4 Status options: Todo, In Progress, Done, and nil.
      options_and_no_value_count = @status_column.settings["options"].count + 1 # +1 for _noValue
      assert_equal 4, options_and_no_value_count

      # assert we have the expected x_axis values
      # Note that 'Todo' is not included because no items have that value.
      # Also note that 'In Progress' is correctly ordered before 'Done', with missing last.
      expected_sorted_x_values = ["In Progress", "Done", MISSING_VALUE_GROUP_KEY]
      assert_equal expected_sorted_x_values, response.chart_data&.x_axis&.values

      # assert that we have the expected grouped assignee values
      expected_sorted_group_values = ["ren", "stimpy", MISSING_VALUE_GROUP_KEY]
      assert_equal expected_sorted_group_values, response.chart_data&.data_series&.map(&:name)

      # assert that we have the expected group data (min of Actuals) for each x_axis value (as floats)
      # note that one Done item applies to both ren and stimpy
      # note that empty Actual values are 0 rather than nil, which is a bit misleading for y-axis aggregations.
      #   For more info, see https://github.com/github/projects-platform/issues/2752
      expected_sorted_group_mins = [
        [200, 99.5, 0], # ren [In Progress, Done, missing]
        [700, 500.75, 0], # stimpy [In Progress, Done, missing]
        [400, 0, 0], # missing [In Progress, Done, missing]
      ]
      assert_equal expected_sorted_group_mins, response.chart_data&.data_series&.map(&:data)
    end

    test "returns chart data for Status taking the MAX over an Actual field" do
      item_count = @current_state_items.count
      populate_elasticsearch_index!(@current_state_items)

      chart_options = Chartable::Options.new(
        x_axis: Chartable::Options::XAxis.new(
          data_source: Chartable::Options::XAxisDataSource.new(
            field_object_or_id: @status_column.to_field,
          )
        ),
        y_axis: Chartable::Options::YAxis.new(
          aggregate: Chartable::Options::YAxisAggregate.new(
            operation: MemexProjectChart::Operation::Max,
            field_object_or_id: @actual_column.to_field,
          )
        )
      )

      query = Search::Queries::MemexProjectItemQuery.insights_query(
        project: @memex,
        viewer: @user,
        chart_options: chart_options,
      )
      response = T.cast(query.execute, Search::Responses::MemexProjectItemResponse)

      assert_equal item_count, response.chart_data&.total_count, "Insights query results did not match the expected number of documents"

      # sanity check that we have 4 Status options: Todo, In Progress, Done, and nil.
      options_and_no_value_count = @status_column.settings["options"].count + 1 # +1 for _noValue
      assert_equal 4, options_and_no_value_count

      # assert we have the expected x_axis values
      # Note that 'Todo' is not included because no items have that value.
      # Also note that 'In Progress' is correctly ordered before 'Done', with missing last.
      expected_sorted_x_values = ["In Progress", "Done", MISSING_VALUE_GROUP_KEY]
      assert_equal expected_sorted_x_values, response.chart_data&.x_axis&.values

      # Since we're not grouping, we just have the one anonymous data series
      expected_data_series = [""]
      assert_equal expected_data_series, response.chart_data&.data_series&.map(&:name)

      # Since we're not grouping, we just have the one data series for max Actual (as floats)
      expected_sorted_group_maxes = [
        [1000, 500.75, 50], # total [In Progress, Done, missing]
      ]

      assert_equal expected_sorted_group_maxes, response.chart_data&.data_series&.map(&:data)
    end

    test "returns grouped chart data for Status grouped by Assignee, taking the MAX over an Actual field" do
      item_count = @current_state_items.count
      populate_elasticsearch_index!(@current_state_items)

      chart_options = Chartable::Options.new(
        x_axis: Chartable::Options::XAxis.new(
          data_source: Chartable::Options::XAxisDataSource.new(
            field_object_or_id: @status_column.to_field,
          ),
          group_by: Chartable::Options::XAxisGroupBy.new(
            field_object_or_id: @assignee_column.to_field,
          )
        ),
        y_axis: Chartable::Options::YAxis.new(
          aggregate: Chartable::Options::YAxisAggregate.new(
            operation: MemexProjectChart::Operation::Max,
            field_object_or_id: @actual_column.to_field,
          )
        )
      )

      query = Search::Queries::MemexProjectItemQuery.insights_query(
        project: @memex,
        viewer: @user,
        chart_options: chart_options,
      )
      response = T.cast(query.execute, Search::Responses::MemexProjectItemResponse)

      assert_equal item_count, response.chart_data&.total_count, "Insights query results did not match the expected number of documents"

      # sanity check that we have 4 Status options: Todo, In Progress, Done, and nil.
      options_and_no_value_count = @status_column.settings["options"].count + 1 # +1 for _noValue
      assert_equal 4, options_and_no_value_count

      # assert we have the expected x_axis values
      # Note that 'Todo' is not included because no items have that value.
      # Also note that 'In Progress' is correctly ordered before 'Done', with missing last.
      expected_sorted_x_values = ["In Progress", "Done", MISSING_VALUE_GROUP_KEY]
      assert_equal expected_sorted_x_values, response.chart_data&.x_axis&.values

      # assert that we have the expected grouped assignee values
      expected_sorted_group_values = ["ren", "stimpy", MISSING_VALUE_GROUP_KEY]
      assert_equal expected_sorted_group_values, response.chart_data&.data_series&.map(&:name)

      # assert that we have the expected group data (max of Actuals) for each x_axis value (as floats)
      # note that one Done item applies to both ren and stimpy
      # note that empty Actual values are 0 rather than nil, which is a bit misleading for y-axis aggregations.
      #   For more info, see https://github.com/github/projects-platform/issues/2752
      expected_sorted_group_maxes = [
        [200, 500.75, 50], # ren [In Progress, Done, missing]
        [1000, 500.75, 0], # stimpy [In Progress, Done, missing]
        [400, 0, 0], # missing [In Progress, Done, missing]
      ]
      assert_equal expected_sorted_group_maxes, response.chart_data&.data_series&.map(&:data)
    end

    test "returns chart data for Status taking the AVG over an Actual field" do
      item_count = @current_state_items.count
      populate_elasticsearch_index!(@current_state_items)

      chart_options = Chartable::Options.new(
        x_axis: Chartable::Options::XAxis.new(
          data_source: Chartable::Options::XAxisDataSource.new(
            field_object_or_id: @status_column.to_field,
          )
        ),
        y_axis: Chartable::Options::YAxis.new(
          aggregate: Chartable::Options::YAxisAggregate.new(
            operation: MemexProjectChart::Operation::Avg,
            field_object_or_id: @actual_column.to_field,
          )
        )
      )

      query = Search::Queries::MemexProjectItemQuery.insights_query(
        project: @memex,
        viewer: @user,
        chart_options: chart_options,
      )
      response = T.cast(query.execute, Search::Responses::MemexProjectItemResponse)

      assert_equal item_count, response.chart_data&.total_count, "Insights query results did not match the expected number of documents"

      # sanity check that we have 4 Status options: Todo, In Progress, Done, and nil.
      options_and_no_value_count = @status_column.settings["options"].count + 1 # +1 for _noValue
      assert_equal 4, options_and_no_value_count

      # assert we have the expected x_axis values
      # Note that 'Todo' is not included because no items have that value.
      # Also note that 'In Progress' is correctly ordered before 'Done', with missing last.
      expected_sorted_x_values = ["In Progress", "Done", MISSING_VALUE_GROUP_KEY]
      assert_equal expected_sorted_x_values, response.chart_data&.x_axis&.values

      # Since we're not grouping, we just have the one anonymous data series
      expected_data_series = [""]
      assert_equal expected_data_series, response.chart_data&.data_series&.map(&:name)

      # Since we're not grouping, we just have the one data series for avg Actual (as floats, rounded to 2 decimal places)
      # Note that 0 values are correctly counted toward the average and empty/missing values are not.
      expected_sorted_group_averages = [
        # (200 + 400 + 1000 + 700) / 4 = 575, (99.5 + 500.75) / 2 = 300.13, (50 + 0) / 2 = 25
        [575.0, 300.13, 25.0], # total [In Progress, Done, missing]
      ]

      assert_equal expected_sorted_group_averages, response.chart_data&.data_series&.map(&:data)
    end

    test "returns grouped chart data for Status grouped by Assignee, taking the AVG over an Actual field" do
      item_count = @current_state_items.count
      populate_elasticsearch_index!(@current_state_items)

      chart_options = Chartable::Options.new(
        x_axis: Chartable::Options::XAxis.new(
          data_source: Chartable::Options::XAxisDataSource.new(
            field_object_or_id: @status_column.to_field,
          ),
          group_by: Chartable::Options::XAxisGroupBy.new(
            field_object_or_id: @assignee_column.to_field,
          )
        ),
        y_axis: Chartable::Options::YAxis.new(
          aggregate: Chartable::Options::YAxisAggregate.new(
            operation: MemexProjectChart::Operation::Avg,
            field_object_or_id: @actual_column.to_field,
          )
        )
      )

      query = Search::Queries::MemexProjectItemQuery.insights_query(
        project: @memex,
        viewer: @user,
        chart_options: chart_options,
      )
      response = T.cast(query.execute, Search::Responses::MemexProjectItemResponse)

      assert_equal item_count, response.chart_data&.total_count, "Insights query results did not match the expected number of documents"

      # sanity check that we have 4 Status options: Todo, In Progress, Done, and nil.
      options_and_no_value_count = @status_column.settings["options"].count + 1 # +1 for _noValue
      assert_equal 4, options_and_no_value_count

      # assert we have the expected x_axis values
      # Note that 'Todo' is not included because no items have that value.
      # Also note that 'In Progress' is correctly ordered before 'Done', with missing last.
      expected_sorted_x_values = ["In Progress", "Done", MISSING_VALUE_GROUP_KEY]
      assert_equal expected_sorted_x_values, response.chart_data&.x_axis&.values

      # assert that we have the expected grouped assignee values
      expected_sorted_group_values = ["ren", "stimpy", MISSING_VALUE_GROUP_KEY]
      assert_equal expected_sorted_group_values, response.chart_data&.data_series&.map(&:name)

      # assert that we have the expected group data (avg of Actuals) for each x_axis value (as floats, rounded to 2 decimal places)
      # note that one Done item applies to both ren and stimpy
      # Note that 0 values are correctly counted toward the average and empty/missing values are not.
      # note that overall empty Actual values are 0 rather than nil, which is a bit misleading for y-axis aggregations.
      #   For more info, see https://github.com/github/projects-platform/issues/2752
      expected_sorted_group_averages = [
        # 200 / 1 = 200, (99.5 + 500.75) / 2 = 300.13, (50 + 0) / 2 = 25
        [200.0, 300.13, 25.0], # ren [In Progress, Done, missing]
        # (1000 +700) / 2 = 850, 500.75 / 1 = 500.75, missing/empty = 0
        [850.0, 500.75, 0.0], # stimpy [In Progress, Done, missing]
        # 400 / 1 = 400, missing/empty = 0, missing/empty = 0
        [400.0, 0.0, 0.0], # missing [In Progress, Done, missing]
      ]
      assert_equal expected_sorted_group_averages, response.chart_data&.data_series&.map(&:data)
    end

    test "returns data_series with same order of static_chart_values from xAxis.dataSource single select field" do
      item_count = 10

      priority_column = create(
        :memex_project_column,
        memex_project: @memex,
        data_type: :single_select,
        settings: {
          # Non-alphabetical order of options
          "options" => [
            { name: "Low" },
            { name: "Medium" },
            { name: "High" },
            { name: "Critical" },
          ]
        }
      )

      priority_options = priority_column.settings["options"]
      low_priority = priority_options.find { |o| o["name"] == "Low" }["id"]
      medium_priority = priority_options.find { |o| o["name"] == "Medium" }["id"]
      high_priority = priority_options.find { |o| o["name"] == "High" }["id"]
      critical_priority = priority_options.find { |o| o["name"] == "Critical" }["id"]

      items = item_count.times.map do
        create(:memex_project_item, content: create(:issue, repository: @repo), memex_project: @memex)
      end
      # items[0] has empty Priority value
      set_column_values(items[1], [[priority_column, critical_priority]])
      set_column_values(items[2], [[priority_column, high_priority]])
      set_column_values(items[3], [[priority_column, high_priority]])
      set_column_values(items[4], [[priority_column, high_priority]])
      set_column_values(items[5], [[priority_column, high_priority]])
      set_column_values(items[6], [[priority_column, low_priority]])
      set_column_values(items[7], [[priority_column, medium_priority]])
      set_column_values(items[8], [[priority_column, medium_priority]])
      set_column_values(items[9], [[priority_column, low_priority]])

      populate_elasticsearch_index!(items)

      chart_options = Chartable::Options.new(
        x_axis: Chartable::Options::XAxis.new(
          data_source: Chartable::Options::XAxisDataSource.new(
            field_object_or_id: priority_column.id,
          ),
        ),
      )

      query = Search::Queries::MemexProjectItemQuery.insights_query(
        project: @memex,
        viewer: @user,
        chart_options:,
      )
      response = T.cast(query.execute, Search::Responses::MemexProjectItemResponse)

      expected_ordered_x_values = ["Low", "Medium", "High", "Critical", MISSING_VALUE_GROUP_KEY]
      assert_equal expected_ordered_x_values, response.chart_data&.x_axis&.values, "Expected xAxis values to return in same order as xAxis.dataSource single select options"
    end

    test "returns grouped chart data_series buckets with the same order as static_chart_values for both xAxis.dataSource and xAxis.groupBy single select fields" do
      item_count = 10

      custom_status_column = create(
        :memex_project_column,
        memex_project: @memex,
        data_type: :single_select,
        settings: {
          "options" => [
            # Non-alphabetical order of options
            { name: "Todo" },
            { name: "In Progress" },
            { name: "Done" },
          ]
        }
      )

      priority_column = create(
        :memex_project_column,
        memex_project: @memex,
        data_type: :single_select,
        settings: {
          "options" => [
            # Non-alphabetical order of options
            { name: "Low" },
            { name: "Medium" },
            { name: "High" },
            { name: "Critical" },
          ]
        }
      )

      custom_status_options = custom_status_column.settings["options"]
      todo = custom_status_options.find { |o| o["name"] == "Todo" }["id"]
      in_progress = custom_status_options.find { |o| o["name"] == "In Progress" }["id"]
      done = custom_status_options.find { |o| o["name"] == "Done" }["id"]

      priority_options = priority_column.settings["options"]
      low_priority = priority_options.find { |o| o["name"] == "Low" }["id"]
      medium_priority = priority_options.find { |o| o["name"] == "Medium" }["id"]
      high_priority = priority_options.find { |o| o["name"] == "High" }["id"]
      critical_priority = priority_options.find { |o| o["name"] == "Critical" }["id"]

      items = item_count.times.map do
        create(:memex_project_item, content: create(:issue, repository: @repo), memex_project: @memex)
      end
      # items[0] has empty Priority and Custom Status values
      set_column_values(items[1], [[custom_status_column, done], [priority_column, critical_priority]])
      set_column_values(items[2], [[custom_status_column, in_progress], [priority_column, high_priority]])
      set_column_values(items[3], [[custom_status_column, done], [priority_column, high_priority]])
      set_column_values(items[4], [[priority_column, high_priority]])
      set_column_values(items[5], [[priority_column, high_priority]])
      set_column_values(items[6], [[custom_status_column, todo]])
      set_column_values(items[7], [[custom_status_column, in_progress], [priority_column, medium_priority]])
      set_column_values(items[8], [[custom_status_column, in_progress], [priority_column, medium_priority]])
      set_column_values(items[9], [[custom_status_column, in_progress], [priority_column, low_priority]])

      populate_elasticsearch_index!(items)

      chart_options = Chartable::Options.new(
        x_axis: Chartable::Options::XAxis.new(
          data_source: Chartable::Options::XAxisDataSource.new(
            field_object_or_id: priority_column.id,
          ),
          group_by: Chartable::Options::XAxisGroupBy.new(
            field_object_or_id: custom_status_column.id,
          )
        )
      )

      query = Search::Queries::MemexProjectItemQuery.insights_query(
        project: @memex,
        viewer: @user,
        chart_options:,
      )
      response = T.cast(query.execute, Search::Responses::MemexProjectItemResponse)

      expected_ordered_x_values = ["Low", "Medium", "High", "Critical", MISSING_VALUE_GROUP_KEY]
      assert_equal expected_ordered_x_values, response.chart_data&.x_axis&.values, "Expected xAxis values to return in same order as xAxis.dataSource single select options"

      expected_ordered_group_values = ["Todo", "In Progress", "Done", MISSING_VALUE_GROUP_KEY]
      assert_equal expected_ordered_group_values, response.chart_data&.data_series&.map(&:name), "Expected data_series buckets to return in same order as xAxis.groupBy single select options"
    end

    test "returns empty non-grouped chart data when no results are found" do
      populate_elasticsearch_index!(@current_state_items)

      chart_options = Chartable::Options.new(
        x_axis: Chartable::Options::XAxis.new(
          data_source: Chartable::Options::XAxisDataSource.new(
            field_object_or_id: @status_column.to_field,
          ),
        ),
      )

      query = Search::Queries::MemexProjectItemQuery.insights_query(
        query: "assignee:404",
        project: @memex,
        viewer: @user,
        chart_options:,
      )
      response = T.cast(query.execute, Search::Responses::MemexProjectItemResponse)
      chart_data = T.must(response.chart_data)

      assert_equal 0, chart_data.total_count, "Expected no results to be found"
      assert_empty chart_data.data_series, "Expected dataSeries to not contain any series"
      assert_empty chart_data.x_axis.values, "Expected xAxis to not return any values"
    end

    test "returns empty grouped chart data when no results are found" do
      populate_elasticsearch_index!(@current_state_items)

      chart_options = Chartable::Options.new(
        x_axis: Chartable::Options::XAxis.new(
          data_source: Chartable::Options::XAxisDataSource.new(
            field_object_or_id: @status_column.to_field,
          ),
          group_by: Chartable::Options::XAxisGroupBy.new(
            field_object_or_id: @assignee_column.to_field,
          ),
        ),
      )

      query = Search::Queries::MemexProjectItemQuery.insights_query(
        query: "assignee:404",
        project: @memex,
        viewer: @user,
        chart_options:,
      )
      response = T.cast(query.execute, Search::Responses::MemexProjectItemResponse)
      chart_data = T.must(response.chart_data)

      assert_equal 0, chart_data.total_count, "Expected no results to be found"
      assert_empty chart_data.data_series, "Expected dataSeries to not contain any series"
      assert_empty chart_data.x_axis.values, "Expected xAxis to not return any values"
    end
  end

  context "historical charts" do
    test "returns time-based historical chart data for all possible states with max range" do
      Timecop.freeze(@time) do
        populate_elasticsearch_index!(@historical_items)

        chart_options = Chartable::Options.new(
          x_axis: Chartable::Options::XAxis.new(
            data_source: Chartable::Options::XAxisDataSource.new(field_object_or_id: "time")
          ),
          time: Chartable::Options::Time.new(period: "max")
        )

        query = Search::Queries::MemexProjectItemQuery.insights_query(
          project: @memex,
          viewer: @user,
          chart_options: chart_options,
        )
        response = T.cast(query.execute, Search::Responses::MemexProjectItemResponse)

        assert_equal @historical_items.count, response.chart_data&.total_count, "Insights query results did not match the expected number of documents"

        # Assert we have the expected x_axis date values.
        # Note that the max range includes the first non-zero date, and the last date is today (UTC).
        first_date = DateTime.parse(10.days.ago.beginning_of_day.to_fs("%Y-%m-%d"))
        today = Time.now.utc.beginning_of_day
        expected_x_values = (first_date..today).map { |date| date.strftime("%Y-%m-%d") }
        assert_equal expected_x_values, response.chart_data&.x_axis&.values

        # Assert that we have the expected burn-up, historical chart data counts for each x_axis value.
        # Note that the cumulative counts for each state, ordered as the Memex client currently expects.
        expected_data_series = [
          ["Open",                 [1, 1, 6, 6, 10, 10, 9, 8, 4, 4, 4]],
          ["Completed",            [0, 0, 0, 0,  0,  0, 0, 1, 4, 4, 4]],
          ["Closed pull requests", [0, 0, 0, 0,  0,  0, 1, 1, 1, 1, 1]],
          ["Not planned",          [0, 0, 0, 0,  0,  0, 1, 1, 1, 1, 1]],
          ["Duplicate",            [0, 0, 0, 0,  0,  0, 1, 1, 2, 2, 2]]
        ]
        assert_equal expected_data_series, response.chart_data&.data_series&.map { |d| [d.name, d.data] }
      end
    end

    test "returns time-based historical chart data, defaulting to 2W time, padding arrays with zeros" do
      Timecop.freeze(@time) do
        populate_elasticsearch_index!(@historical_items)

        chart_options = Chartable::Options.new(
          x_axis: Chartable::Options::XAxis.new(
            data_source: Chartable::Options::XAxisDataSource.new(field_object_or_id: "time")
          )
        )

        query = Search::Queries::MemexProjectItemQuery.insights_query(
          project: @memex,
          viewer: @user,
          chart_options: chart_options,
        )
        response = T.cast(query.execute, Search::Responses::MemexProjectItemResponse)

        assert_equal @historical_items.count, response.chart_data&.total_count, "Insights query results did not match the expected number of documents"

        # Assert we have the expected x_axis date values.
        # Note that the default 2W range starts 2 weeks ago, and the last date is today (UTC).
        first_date = DateTime.parse(14.days.ago.beginning_of_day.to_fs("%Y-%m-%d"))
        today = Time.now.utc.beginning_of_day
        expected_x_values = (first_date..today).map { |date| date.strftime("%Y-%m-%d") }
        assert_equal expected_x_values, response.chart_data&.x_axis&.values

        # Assert that we have the expected burn-up, historical chart data counts for each x_axis value.
        # Note that the cumulative counts for each state, ordered as the Memex client currently expects.
        # Note the additional 0's at the front of each array for the 2-week default time range.
        expected_data_series = [
          ["Open",                 [0, 0, 0, 0, 1, 1, 6, 6, 10, 10, 9, 8, 4, 4, 4]],
          ["Completed",            [0, 0, 0, 0, 0, 0, 0, 0,  0,  0, 0, 1, 4, 4, 4]],
          ["Closed pull requests", [0, 0, 0, 0, 0, 0, 0, 0,  0,  0, 1, 1, 1, 1, 1]],
          ["Not planned",          [0, 0, 0, 0, 0, 0, 0, 0,  0,  0, 1, 1, 1, 1, 1]],
          ["Duplicate",            [0, 0, 0, 0, 0, 0, 0, 0,  0,  0, 1, 1, 2, 2, 2]]
        ]
        assert_equal expected_data_series, response.chart_data&.data_series&.map { |d| [d.name, d.data] }
      end
    end

    test "returns time-based historical chart data with a specified time range" do
      Timecop.freeze(@time) do
        populate_elasticsearch_index!(@historical_items)

        start_date = 3.days.ago.to_date
        end_date = 1.day.ago.to_date

        chart_options = Chartable::Options.new(
          x_axis: Chartable::Options::XAxis.new(
            data_source: Chartable::Options::XAxisDataSource.new(field_object_or_id: "time")
          ),
          time: Chartable::Options::Time.new(
            period: "custom",
            start_date: start_date.strftime("%Y-%m-%d"),
            end_date: end_date.strftime("%Y-%m-%d")
          )
        )

        query = Search::Queries::MemexProjectItemQuery.insights_query(
          project: @memex,
          viewer: @user,
          chart_options: chart_options,
        )
        response = T.cast(query.execute, Search::Responses::MemexProjectItemResponse)

        assert_equal @historical_items.count, response.chart_data&.total_count, "Insights query results did not match the expected number of documents"

        # Assert we have the expected x_axis date values.
        # Note that the default max range includes start_date through end_date, inclusive (UTC).
        expected_x_values = (start_date..end_date).map { |date| date.strftime("%Y-%m-%d") }
        assert_equal expected_x_values, response.chart_data&.x_axis&.values

        # Assert that we have the expected burn-up, historical chart data counts for each x_axis value.
        # Note that the cumulative counts for each state, ordered as the Memex client currently expects.
        # Note that all non-open subtract counts from the previous day, reseting to 0.
        # Note that arrays "Not planned" and "Closed pull requests" are omitted since they're [0, 0, 0].
        expected_data_series = [
          ["Open",                 [8, 4, 4]],
          ["Completed",            [1, 4, 4]],
          ["Duplicate",            [0, 1, 1]]
        ]
        assert_equal expected_data_series, response.chart_data&.data_series&.map { |d| [d.name, d.data] }
      end
    end

    test "returns time-based historical chart data by week for 5+ year range using a custom period" do
      # Hard-coding this test to Wednesday January 8, 2025 to ensure consistent week boundaries for binned data.
      time = Time.parse("2025-01-08 14:00:00 UTC")
      items = create_historical_test_items(time: time, repo: @repo, memex: @memex)
      items[:issue_items].first.content.update!(created_at: time.years_ago(10)) # Crazy old issue created 10 years ago (Thu, 08 Jan 2015).
      older_historical_items = items[:issue_items] + items[:pr_items] + items[:draft_items]

      Timecop.freeze(time) do
        populate_elasticsearch_index!(older_historical_items)

        end_date = time.to_date
        start_date = end_date.years_ago(5).prev_day

        chart_options = Chartable::Options.new(
          x_axis: Chartable::Options::XAxis.new(
            data_source: Chartable::Options::XAxisDataSource.new(field_object_or_id: "time")
          ),
          time: Chartable::Options::Time.new(
            period: "custom",
            start_date: start_date.strftime("%Y-%m-%d"),
            end_date: end_date.strftime("%Y-%m-%d")
          )
        )

        query = Search::Queries::MemexProjectItemQuery.insights_query(
          project: @memex,
          viewer: @user,
          chart_options: chart_options,
        )
        response = T.cast(query.execute, Search::Responses::MemexProjectItemResponse)


        # Assert we have the expected x_axis date values, with weekly Monday intervals.
        # Note that the default max range includes start_date through end_date, inclusive (UTC).
        first_date = start_date.prev_occurring(:monday)
        last_date = end_date.prev_occurring(:monday)

        assert_equal first_date, DateTime.parse("2020-01-06") # Monday January 6, 2020 (first Monday before 5 years before 2025-01-08)
        assert_equal last_date, DateTime.parse("2025-01-06") # Monday January 6, 2025 (last Monday of the time range ending Wed 2025-01-08)

        expected_x_values = (first_date..last_date).step(7).map { |date| date.strftime("%Y-%m-%d") }
        actual_x_values = response.chart_data&.x_axis&.values
        assert_equal first_date.strftime("%Y-%m-%d"), actual_x_values&.first
        assert_equal last_date.strftime("%Y-%m-%d"), actual_x_values&.last
        assert_equal 262, actual_x_values&.length
        assert_equal expected_x_values, actual_x_values

        # Assert that we have the expected burn-up, historical chart data counts for each x_axis value.
        # Note that the cumulative counts for each state, ordered as the Memex client currently expects.
        # Note the 262 weeks of data, including the first week with the crazy old issue.
        leading_zeros = Array.new(257, 0)
        leading_ones = Array.new(257, 1)
        expected_data_series = [
          ["Open",                 leading_ones +  [1, 1, 2, 8, 4]],
          ["Completed",            leading_zeros + [0, 0, 0, 1, 4]],
          ["Closed pull requests", leading_zeros + [0, 0, 0, 1, 1]],
          ["Not planned",          leading_zeros + [0, 0, 0, 1, 1]],
          ["Duplicate",            leading_zeros + [0, 0, 0, 1, 2]]
        ]
        assert_equal expected_data_series, response.chart_data&.data_series&.map { |d| [d.name, d.data] }
      end
    end

    test "returns time-based historical chart data by week for 5+ year range using the max period" do
      # Hard-coding this test to Wednesday January 8, 2025 to ensure consistent week boundaries for binned data.
      time = Time.parse("2025-01-08 14:00:00 UTC")
      items = create_historical_test_items(time: time, repo: @repo, memex: @memex)
      items[:issue_items].first.content.update!(created_at: time.years_ago(10)) # Crazy old issue created 10 years ago (Thu, 08 Jan 2015).
      older_historical_items = items[:issue_items] + items[:pr_items] + items[:draft_items]

      Timecop.freeze(time) do
        populate_elasticsearch_index!(older_historical_items)

        chart_options = Chartable::Options.new(
          x_axis: Chartable::Options::XAxis.new(
            data_source: Chartable::Options::XAxisDataSource.new(field_object_or_id: "time")
          ),
          time: Chartable::Options::Time.new(
            period: "max",
          )
        )

        query = Search::Queries::MemexProjectItemQuery.insights_query(
          project: @memex,
          viewer: @user,
          chart_options: chart_options,
        )
        response = T.cast(query.execute, Search::Responses::MemexProjectItemResponse)

        # Assert we have the expected x_axis date values, with weekly Monday intervals.
        # Note that the default max range includes start_date through end_date, inclusive (UTC).
        start_date = time.years_ago(10).to_date
        end_date = time.to_date

        # Elasticsearch weekly date histogram bins are Monday-Sunday
        first_date = start_date.prev_occurring(:monday)
        last_date = end_date.prev_occurring(:monday)

        assert_equal first_date, DateTime.parse("2015-01-05") # Monday January 5, 2015 (first Monday before 10 years before Wednesday 2025-01-08)
        assert_equal last_date, DateTime.parse("2025-01-06") # Monday January 6, 2025 (last Monday of the time range ending Wednesday 2025-01-08)

        expected_x_values = (first_date..last_date).step(7).map { |date| date.strftime("%Y-%m-%d") }
        actual_x_values = response.chart_data&.x_axis&.values
        assert_equal first_date.strftime("%Y-%m-%d"), actual_x_values&.first
        assert_equal last_date.strftime("%Y-%m-%d"), actual_x_values&.last
        assert_equal 523, actual_x_values&.length
        assert_equal expected_x_values, actual_x_values

        # Assert that we have the expected burn-up, historical chart data counts for each x_axis value.
        # Note that the cumulative counts for each state, ordered as the Memex client currently expects.
        # Note the 523 weeks of data, including the first week with the crazy old issue.
        leading_zeros = Array.new(518, 0)
        leading_ones = Array.new(518, 1)
        expected_data_series = [
          ["Open",                 leading_ones +  [1, 1, 2, 8, 4]],
          ["Completed",            leading_zeros + [0, 0, 0, 1, 4]],
          ["Closed pull requests", leading_zeros + [0, 0, 0, 1, 1]],
          ["Not planned",          leading_zeros + [0, 0, 0, 1, 1]],
          ["Duplicate",            leading_zeros + [0, 0, 0, 1, 2]]
        ]
        assert_equal expected_data_series, response.chart_data&.data_series&.map { |d| [d.name, d.data] }
      end
    end

    test "returns time-based historical chart data by week for 5+ year range with max at Monday/Sunday boundaries" do
      # Hard-coding this test to Wednesday January 8, 2025 to ensure consistent week boundaries for binned data.
      time = Time.parse("2025-01-08 14:00:00 UTC")  # Wednesday January 8, 2025
      monday_10_years_ago = time.years_ago(10).prev_occurring(:monday) # Monday January 5, 2015
      following_sunday = time.next_occurring(:sunday) # Sunday January 12, 2025

      Timecop.freeze(following_sunday) do
        issues = [
          create(:issue, repository: @repo, created_at: monday_10_years_ago),
          create(:issue, repository: @repo, created_at: 14.days.ago, state: :closed, closed_at: 2.days.ago)
        ]
        issue_items = issues.map { |issue| create(:memex_project_item, content: issue, memex_project: @memex) }

        populate_elasticsearch_index!(issue_items)

        chart_options = Chartable::Options.new(
          x_axis: Chartable::Options::XAxis.new(
            data_source: Chartable::Options::XAxisDataSource.new(field_object_or_id: "time")
          ),
          time: Chartable::Options::Time.new(
            period: "max",
          )
        )

        query = Search::Queries::MemexProjectItemQuery.insights_query(
          project: @memex,
          viewer: @user,
          chart_options: chart_options,
        )
        response = T.cast(query.execute, Search::Responses::MemexProjectItemResponse)

        # Assert we have the expected x_axis date values for max, with weekly Monday intervals.
        # Starting on the first Monday bin when the oldest issue was created,
        # and ending on the following Sunday when the query was executed.
        start_date = monday_10_years_ago.to_date
        end_date = following_sunday.to_date

        # Elasticsearch weekly date histogram bins are Monday dates representing that week of Monday-Sunday
        first_date = start_date
        last_date = end_date.prev_occurring(:monday)

        assert_equal first_date, DateTime.parse("2015-01-05") # Monday January 5, 2015 (first Monday before 10 years before Wednesday 2025-01-08)
        assert_equal last_date, DateTime.parse("2025-01-06") # Monday January 6, 2025 (last Monday of the time range ending Sunday 2025-01-12)

        expected_x_values = (first_date..last_date).step(7).map { |date| date.strftime("%Y-%m-%d") }
        actual_x_values = response.chart_data&.x_axis&.values
        assert_equal first_date.strftime("%Y-%m-%d"), actual_x_values&.first
        assert_equal last_date.strftime("%Y-%m-%d"), actual_x_values&.last
        assert_equal 523, actual_x_values&.length
        assert_equal expected_x_values, actual_x_values

        # Assert that we have the expected burn-up, historical chart data counts for each x_axis value.
        # Note that the cumulative counts for each non-empty state array, ordered as the Memex client currently expects.
        # Note the 523 weeks of data, including the first week with the crazy old issue.
        leading_zeros = Array.new(518, 0)
        leading_ones = Array.new(518, 1)
        expected_data_series = [
          ["Open",                 leading_ones +  [1, 1, 2, 2, 1]],
          ["Completed",            leading_zeros + [0, 0, 0, 0, 1]],
        ]
        assert_equal expected_data_series, response.chart_data&.data_series&.map { |d| [d.name, d.data] }
      end
    end

    test "validates time ranges and limits" do
      Timecop.freeze(@time) do
        populate_elasticsearch_index!(@historical_items)
        x_axis = Chartable::Options::XAxis.new(
          data_source: Chartable::Options::XAxisDataSource.new(field_object_or_id: "time")
        )

        # Start and end dates must be in the correct format YYYY-MM-DD
        start_date = @time.to_date.strftime("%Y-%m-%d")
        end_date = "55-555-555"
        assert_raises_with_message(ArgumentError, "time.endDate must be in the format YYYY-MM-DD") do
          Search::Queries::MemexProjectItemQuery.insights_query(
            project: @memex,
            viewer: @user,
            chart_options: Chartable::Options.new(x_axis:, time: Chartable::Options::Time.new(period: "custom", start_date:, end_date:))
          ).execute
        end

        # Start and end dates must be valid
        start_date = @time.to_date.strftime("%Y-%m-%d")
        end_date = "2024-13-99"
        assert_raises_with_message(ArgumentError, "time.endDate must be a valid date") do
          Search::Queries::MemexProjectItemQuery.insights_query(
            project: @memex,
            viewer: @user,
            chart_options: Chartable::Options.new(x_axis:, time: Chartable::Options::Time.new(period: "custom", start_date:, end_date:))
          ).execute
        end

        # Start date must be before end date
        start_date = @time.to_date.strftime("%Y-%m-%d")
        end_date = 1.year.ago.to_date.strftime("%Y-%m-%d")
        assert_raises_with_message(ArgumentError, "time.startDate cannot be later than time.endDate") do
          Search::Queries::MemexProjectItemQuery.insights_query(
            project: @memex,
            viewer: @user,
            chart_options: Chartable::Options.new(x_axis:, time: Chartable::Options::Time.new(period: "custom", start_date:, end_date:))
          ).execute
        end

        # Range must be less than 50 years
        start_date = 105.years.ago.to_date.strftime("%Y-%m-%d")
        end_date = 1.year.ago.to_date.strftime("%Y-%m-%d")
        assert_raises_with_message(ArgumentError, "time range cannot be greater than 50 years") do
          Search::Queries::MemexProjectItemQuery.insights_query(
            project: @memex,
            viewer: @user,
            chart_options: Chartable::Options.new(x_axis:, time: Chartable::Options::Time.new(period: "custom", start_date:, end_date:))
          ).execute
        end
      end
    end

    test "returns time-based historical chart data, omitting empty data series from filtering" do
      Timecop.freeze(@time) do
        populate_elasticsearch_index!(@historical_items)

        chart_options = Chartable::Options.new(
          x_axis: Chartable::Options::XAxis.new(
            data_source: Chartable::Options::XAxisDataSource.new(field_object_or_id: "time")
          ),
          time: Chartable::Options::Time.new(period: "max")
        )

        query = Search::Queries::MemexProjectItemQuery.insights_query(
          project: @memex,
          viewer: @user,
          chart_options: chart_options,
          query: "is:issue"
        )
        response = T.cast(query.execute, Search::Responses::MemexProjectItemResponse)

        issues = @historical_items.select { |item| %[Issue DraftIssue].include? item.content_type }
        refute_equal issues.length, @historical_items.length, "MemexProjectItem fixtures did not include non-issues"
        assert_equal issues.length, response.chart_data&.total_count, "Insights query results did not match the expected number of documents"

        # Assert we have the expected x_axis date values.
        # Note that the default max range includes the first non-zero date, and the last date is today (UTC).
        # With PRs filtered out, the first non-zero date is 8 days ago.
        first_date = DateTime.parse(8.days.ago.beginning_of_day.to_fs("%Y-%m-%d"))
        today = Time.now.utc.beginning_of_day
        expected_x_values = (first_date..today).map { |date| date.strftime("%Y-%m-%d") }
        assert_equal expected_x_values, response.chart_data&.x_axis&.values

        # Assert that we have the expected burn-up, historical chart data counts for each x_axis value.
        # Note that the cumulative counts for each state, ordered as the Memex client currently expects.
        expected_data_series = [
          ["Open",                 [4, 4, 7, 7, 6, 6, 3, 3, 3]],
          ["Completed",            [0, 0, 0, 0, 0, 0, 2, 2, 2]],
          ["Not planned",          [0, 0, 0, 0, 1, 1, 1, 1, 1]],
          ["Duplicate",            [0, 0, 0, 0, 1, 1, 2, 2, 2]]
        ]
        assert_equal expected_data_series, response.chart_data&.data_series&.map { |d| [d.name, d.data] }
      end
    end

    test "returns time-based historical chart data for all possible states with max range, taking the SUM over an Estimate field" do
      Timecop.freeze(@time) do
        populate_elasticsearch_index!(@historical_items)

        chart_options = Chartable::Options.new(
          x_axis: Chartable::Options::XAxis.new(
            data_source: Chartable::Options::XAxisDataSource.new(field_object_or_id: "time")
          ),
          time: Chartable::Options::Time.new(period: "max"),
          y_axis: Chartable::Options::YAxis.new(
            aggregate: Chartable::Options::YAxisAggregate.new(
              operation: MemexProjectChart::Operation::Sum,
              field_object_or_id: @estimate_column.to_field
            )
          )
        )

        query = Search::Queries::MemexProjectItemQuery.insights_query(
          project: @memex,
          viewer: @user,
          chart_options: chart_options,
        )
        response = T.cast(query.execute, Search::Responses::MemexProjectItemResponse)

        assert_equal @historical_items.count, response.chart_data&.total_count, "Insights query results did not match the expected number of documents"

        # Assert we have the expected x_axis date values.
        # Note that the max range includes the first non-zero date, and the last date is today (UTC).
        first_date = DateTime.parse(10.days.ago.beginning_of_day.to_fs("%Y-%m-%d"))
        today = Time.now.utc.beginning_of_day
        expected_x_values = (first_date..today).map { |date| date.strftime("%Y-%m-%d") }
        assert_equal expected_x_values, response.chart_data&.x_axis&.values

        # Assert that we have the expected burn-up, historical chart data SUMs for each x_axis value (as floats, rounded to 2 decimal places).
        # Note that the cumulative SUMs for each state, ordered as the Memex client currently expects.
        #   Shown here are the original counts for clarity.
        #   All 12 items have an Estimate of 5 for ease of manual calculation.
        # ["Open",                 [1, 1, 6, 6, 10, 10, 9, 8, 4, 4, 4]],
        # ["Completed",            [0, 0, 0, 0,  0,  0, 0, 1, 4, 4, 4]],
        # ["Closed pull requests", [0, 0, 0, 0,  0,  0, 1, 1, 1, 1, 1]],
        # ["Not planned",          [0, 0, 0, 0,  0,  0, 1, 1, 1, 1, 1]],
        # ["Duplicate",            [0, 0, 0, 0,  0,  0, 1, 1, 2, 2, 2]]

        expected_data_series = [
          ["Open",                 [5.0, 5.0, 30.01, 30.01, 50.01, 50.01, 45.01, 40.01, 20.0,  20.0,  20.0]],
          ["Completed",            [0.0, 0.0, 0.0,   0.0,   0.0,   0.0,   0.0,   5.0,   20.01, 20.01, 20.01]],
          ["Closed pull requests", [0.0, 0.0, 0.0,   0.0,   0.0,   0.0,   5.0,   5.0,   5.0,   5.0,   5.0]],
          ["Not planned",          [0.0, 0.0, 0.0,   0.0,   0.0,   0.0,   5.0,   5.0,   5.0,   5.0,   5.0]],
          ["Duplicate",            [0.0, 0.0, 0.0,   0.0,   0.0,   0.0,   5.0,   5.0,   10.0,  10.0,  10.0]]
        ]
        assert_equal expected_data_series, response.chart_data&.data_series&.map { |d| [d.name, d.data] }
      end
    end

    test "returns time-based historical chart data with item counts for deprecated, legacy requests for MIN, MAX, or AVG" do
      Timecop.freeze(@time) do
        populate_elasticsearch_index!(@historical_items)

        # Let's first get the chart data when the default item counts are requested
        count_chart_options = Chartable::Options.new(
          x_axis: Chartable::Options::XAxis.new(
            data_source: Chartable::Options::XAxisDataSource.new(field_object_or_id: "time")
          ),
          time: Chartable::Options::Time.new(period: "max")
        )
        count_query = Search::Queries::MemexProjectItemQuery.insights_query(
          project: @memex,
          viewer: @user,
          chart_options: count_chart_options,
        )
        response = T.cast(count_query.execute, Search::Responses::MemexProjectItemResponse)

        # This is the expected data series for the default item counts
        count_data_series = response.chart_data&.data_series&.map { |d| [d.name, d.data] }

        # Now let's iterate over the deprecated operations and assert that the returned chart data matches the count data
        deprecated_operations = [MemexProjectChart::Operation::Min, MemexProjectChart::Operation::Max, MemexProjectChart::Operation::Avg]
        deprecated_operations.each do |deprecated_operation|
          chart_options = Chartable::Options.new(
            x_axis: Chartable::Options::XAxis.new(
              data_source: Chartable::Options::XAxisDataSource.new(field_object_or_id: "time")
            ),
            time: Chartable::Options::Time.new(period: "max"),
            y_axis: Chartable::Options::YAxis.new(
              aggregate: Chartable::Options::YAxisAggregate.new(
                operation: deprecated_operation,
                field_object_or_id: @estimate_column.to_field
              )
            )
          )

          query = Search::Queries::MemexProjectItemQuery.insights_query(
            project: @memex,
            viewer: @user,
            chart_options: chart_options,
          )
          response = T.cast(query.execute, Search::Responses::MemexProjectItemResponse)
          deprecated_response_data = response.chart_data&.data_series&.map { |d| [d.name, d.data] }

          assert_equal count_data_series, deprecated_response_data, "Deprecated operation '#{deprecated_operation.serialize}' did not return the expected item counts"
        end
      end
    end

    test "returns time-based historical chart data with a specified time range, taking the SUM over an Estimate field" do
      Timecop.freeze(@time) do
        populate_elasticsearch_index!(@historical_items)

        start_date = 3.days.ago.to_date
        end_date = 1.day.ago.to_date

        chart_options = Chartable::Options.new(
          x_axis: Chartable::Options::XAxis.new(
            data_source: Chartable::Options::XAxisDataSource.new(field_object_or_id: "time")
          ),
          time: Chartable::Options::Time.new(
            period: "custom",
            start_date: start_date.strftime("%Y-%m-%d"),
            end_date: end_date.strftime("%Y-%m-%d")
          ),
          y_axis: Chartable::Options::YAxis.new(
            aggregate: Chartable::Options::YAxisAggregate.new(
              operation: MemexProjectChart::Operation::Sum,
              field_object_or_id: @estimate_column.to_field
            )
          )
        )

        query = Search::Queries::MemexProjectItemQuery.insights_query(
          project: @memex,
          viewer: @user,
          chart_options: chart_options,
        )
        response = T.cast(query.execute, Search::Responses::MemexProjectItemResponse)

        assert_equal @historical_items.count, response.chart_data&.total_count, "Insights query results did not match the expected number of documents"

        # Assert we have the expected x_axis date values.
        # Note that the max range includes the first non-zero date, and the last date is today (UTC).
        expected_x_values = (start_date..end_date).map { |date| date.strftime("%Y-%m-%d") }
        assert_equal expected_x_values, response.chart_data&.x_axis&.values

        # Assert that we have the expected burn-up, historical chart data SUMs for each x_axis value (as floats, rounded to 2 decimal places).
        # Note that the cumulative SUMs for each state, ordered as the Memex client currently expects.
        # Note that all non-open subtract SUMs from the previous day, reseting to 0.
        # Note that arrays "Not planned" and "Closed pull requests" are omitted since they're [0, 0, 0].
        #   Shown here are the original counts for clarity.
        #   All 12 items have an Estimate of 5 for ease of manual calculation.
        # ["Open",                 [8, 4, 4]],
        # ["Completed",            [1, 4, 4]],
        # ["Duplicate",            [0, 1, 1]]

        expected_data_series = [
          ["Open",                 [40.01, 20.0,  20.0]],
          ["Completed",            [5.0,   20.01, 20.01]],
          ["Duplicate",            [0.0,   5.0,   5.0]]
        ]
        assert_equal expected_data_series, response.chart_data&.data_series&.map { |d| [d.name, d.data] }
      end
    end

    test "returns empty time-based historical chart data when no results are found" do
      populate_elasticsearch_index!(@historical_items)

      chart_options = Chartable::Options.new(
        x_axis: Chartable::Options::XAxis.new(
          data_source: Chartable::Options::XAxisDataSource.new(field_object_or_id: "time")
        ),
      )

      query = Search::Queries::MemexProjectItemQuery.insights_query(
        query: "assignee:404",
        project: @memex,
        viewer: @user,
        chart_options:,
      )
      response = T.cast(query.execute, Search::Responses::MemexProjectItemResponse)
      chart_data = T.must(response.chart_data)

      assert_equal 0, chart_data.total_count, "Expected no results to be found"
      assert_empty chart_data.data_series, "Expected dataSeries to not contain any series"
      assert_empty chart_data.x_axis.values, "Expected xAxis to not return any values"
    end
  end

  # Sets multiple column values when requested as an array of [column, value] pairs.
  sig { params(item: MemexProjectItem, column_value_pairs: T::Array[T::Array[T.untyped]]).returns(T.untyped) }
  private def set_column_values(item, column_value_pairs)
    column_value_pairs.each do |pair|
      item.set_column_value(pair[0], pair[1], @user)
    end
  end
end
