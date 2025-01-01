# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexesInsightsHelper::QueryBuilderTest < GitHub::TestCase
  fixtures do
    @memex = create(:memex_project, id: 15)
  end

  def project_item_id_clause
    "P.ProjectItemId IN (1, 2, 3)\n"
  end

  def date_selector
    "<= 2023-02-01"
  end

  test "it handles group_by status as a special case" do
    query = MemexesInsightsHelper::QueryBuilder.new(
      memex_org: @memex,
      date_selector: date_selector,
      project_item_id_clause: project_item_id_clause,
      group_by: {
        column: "Status",
        data_type: "singleSelect"
      },
      query_labels_historical_data: false,
    ).build

    assert_equal <<~QUERY.squish, query
      SELECT P.Date, COUNT(P.ProjectItemId) as count, COALESCE(P.Status, 'No Status') as Status
      FROM ProjectItemSnapshot P
      WHERE P.ProjectId = 15 AND P.DateKey <= 2023-02-01 AND P.ProjectItemId IN (1, 2, 3) AND Archived = 0
      GROUP BY P.Date, P.Status, P.StatusRank
      ORDER BY P.StatusRank DESC
    QUERY
  end
  test "it escapes group_by column name for single select fields" do
    # square brackets are escaped
    query = MemexesInsightsHelper::QueryBuilder.new(
      memex_org: @memex,
      date_selector: date_selector,
      project_item_id_clause: project_item_id_clause,
      group_by: {
        column: "[ColumnName]",
        data_type: "singleSelect"
      },
      query_labels_historical_data: false,
    ).build

    assert_equal <<~QUERY.squish, query
    SELECT P.Date, COUNT(P.ProjectItemId) as count, COALESCE(S.Name, 'No Value') as [[ColumnName]]]
    FROM ProjectItemSnapshot P
    LEFT OUTER JOIN SingleSelectColumnSetting S ON S.SingleSelectKey = P.[[ColumnName]]Key]
    WHERE P.ProjectId = 15 AND P.DateKey <= 2023-02-01 AND P.ProjectItemId IN (1, 2, 3) AND Archived = 0
    GROUP BY P.Date, S.Name, S.OptionRank
    ORDER BY S.OptionRank
    QUERY
  end

  test "it escapes group_by column name for iteration fields" do
    # square brackets are escaped
    query = MemexesInsightsHelper::QueryBuilder.new(
      memex_org: @memex,
      date_selector: date_selector,
      project_item_id_clause: project_item_id_clause,
      group_by: {
        column: "[SomeData]",
        data_type: "iteration"
      },
      query_labels_historical_data: false,
    ).build

    assert_equal <<~QUERY.squish, query
    SELECT P.Date, COUNT(P.ProjectItemId) as count, COALESCE(I.Name, 'No Iteration') as [[SomeData]]]
    FROM ProjectItemSnapshot P
    LEFT OUTER JOIN Iteration I ON I.IterationKey = P.[[SomeData]]Key]
    WHERE P.ProjectId = 15 AND P.DateKey <= 2023-02-01 AND P.ProjectItemId IN (1, 2, 3) AND Archived = 0
    GROUP BY P.Date, I.Name, I.StartDateKey
    ORDER BY I.StartDateKey
    QUERY
  end

  context "#escape_column_name" do
    test "it adds a single pair of brackets around the given value" do
      assert_equal "[ColumnName]", MemexesInsightsHelper::QueryBuilder.escape_column_name("ColumnName")
    end
    test "it escapes square brackets" do
      assert_equal "[[ColumnName]]]", MemexesInsightsHelper::QueryBuilder.escape_column_name("[ColumnName]")
    end
    test "it does not escape single quotes" do
      assert_equal "[It's quoted]", MemexesInsightsHelper::QueryBuilder.escape_column_name("It's quoted")
    end
    test "it removes newlines" do
      assert_equal "[Column Name]", MemexesInsightsHelper::QueryBuilder.escape_column_name("Column\nName")
      assert_equal "[Column Name]", MemexesInsightsHelper::QueryBuilder.escape_column_name("Column\rName")
      assert_equal "[Column  Name]", MemexesInsightsHelper::QueryBuilder.escape_column_name("Column\r\nName")
    end
  end
end
