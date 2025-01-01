# typed: true
# frozen_string_literal: true

require "test_helper"

class GroupTest < GitHub::TestCase
  fixtures do
    @user             = create(:user)
    @org              = create(:organization, admin: @user)
    @memex            = create(:memex_project, owner: @org)
    @text_column      = create(:memex_project_column, user_defined: true, data_type: :text, memex_project: @memex)
    @number_column    = create(:memex_project_column, user_defined: true, data_type: :number, memex_project: @memex)
    @date_column      = create(:memex_project_column, user_defined: true, data_type: :date, memex_project: @memex)
    @iteration_column = create(:iteration_memex_column_with_completed_iterations, memex_project: @memex)
    @status_column    = @memex.status_column
  end

  test "data_type delegates to column" do
    group = group(column: @date_column)

    assert_equal @date_column.data_type, group.data_type
  end

  test "column_id delegates to column#synthetic_id" do
    group = group(column: @date_column)

    assert_equal @date_column.synthetic_id, group.column_id
  end

  context "equality" do
    test "== compares column id and value" do
      value = Date.parse("2001-01-02")

      group1 = group(column: @date_column, value: value)
      group2 = group(column: @date_column, value: value)

      # assert_equal will use == to compare
      assert_equal group1, group2
    end

    test "different columns do not equal" do
      value = Date.parse("2001-01-02")

      group1 = group(column: @date_column, value: value)
      group2 = group(column: @text_column, value: value)

      # refute_equal will use != to compare
      refute_equal group1, group2
    end
  end

  context "#sort" do
    test "text columns are sorted by title" do
      group1 = group(column: @text_column, title: "fff")
      group2 = group(column: @text_column, title: "ddd")

      assert_equal [group2, group1], [group1, group2].sort
    end

    test "date columns are sorted by value" do
      group1 = group(column: @text_column, value: Date.parse("2021-01-02"))
      group2 = group(column: @text_column, value: Date.parse("2001-01-01"))

      assert_equal [group2, group1], [group1, group2].sort
    end

    test "iteration columns are sorted by their iteration ordering" do
      value1 = @iteration_column.settings_all_iterations.second["id"]
      value2 = @iteration_column.settings_all_iterations.first["id"]
      group1 = group(column: @iteration_column, value: value1)
      group2 = group(column: @iteration_column, value: value2)

      assert_equal [group2, group1], [group1, group2].sort
    end

    test "single select columns are sorted by their option ordering" do
      value1 = @status_column.settings["options"].second["id"]
      value2 = @status_column.settings["options"].first["id"]
      group1 = group(column: @status_column, value: value1)
      group2 = group(column: @status_column, value: value2)

      assert_equal [group2, group1], [group1, group2].sort
    end
  end

  context "#sort_value" do
    test "date data type returns value" do
      value = Date.parse("2001-01-02")

      group = group(column: @date_column, value: value)

      assert_equal value, group.sort_value
    end

    test "number data type returns value" do
      value = 2.5

      group = group(column: @number_column, value: value)

      assert_equal value, group.sort_value
    end

    test "iteration data type returns positional iteration index" do
      value = @iteration_column.settings_all_iterations.third["id"]

      group = group(column: @iteration_column, value: value)

      assert_equal 2, group.sort_value
    end

    test "single select data type returns positional option index" do
      value = @status_column.settings["options"].second["id"]

      group = group(column: @status_column, value: value)

      assert_equal 1, group.sort_value
    end

    test "text data type returns title" do
      title = "foo"

      group = group(column: @text_column, title: title)

      assert_equal title, group.sort_value
    end
  end

  def group(column:, title: "", value: nil)
    MemexProject::Group.new(column: column, title: title, value: value)
  end
end
