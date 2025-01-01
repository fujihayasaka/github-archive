# typed: true
# frozen_string_literal: true
require "test_helper"

class MemexProjectIterationRangeComparatorTest < GitHub::TestCase
  include MemexHelpers

  fixtures do
    @memex = create(:memex_project)
    @iteration_field = create(:iteration_memex_column_with_completed_iterations, memex_project: @memex).to_field
    @iterations = @iteration_field.settings["configuration"]["iterations"]

    @iteration_1_title = @iterations[0]["title"]
    @iteration_1_start_date = @iterations[0]["start_date"]

    @iteration_2_title = @iterations[1]["title"]
    @iteration_2_start_date = @iterations[1]["start_date"]
  end

  test "range between Iteration 1..Iteration 2" do
    values = ["#{@iteration_1_title}..#{@iteration_2_title}"]
    iteration_filter_values = MemexProject::IterationRangeComparator.new(values)
    patterns = iteration_filter_values.range_patterns
    expected_pattern = { gte: @iteration_1_title, lte: @iteration_2_title }
    range_clause = iteration_filter_values.range_clause(@iterations, patterns)
    expected_clause = { gte: @iteration_1_start_date, lte: @iteration_2_start_date }

    assert_equal expected_pattern, patterns
    assert_equal expected_clause, range_clause
  end

  test "range greater or equal than >=Iteration 2" do
    values = [">=#{@iteration_2_title}"]
    iteration_filter_values = MemexProject::IterationRangeComparator.new(values)
    patterns = iteration_filter_values.range_patterns
    expected_pattern = { gte: @iteration_2_title }
    range_clause = iteration_filter_values.range_clause(@iterations, patterns)
    expected_clause = { gte: @iteration_2_start_date }

    assert_equal expected_pattern, patterns
    assert_equal expected_clause, range_clause
  end

  test "range greater than Iteration 1..*" do
    values = ["#{@iteration_1_title}..*"]
    iteration_filter_values = MemexProject::IterationRangeComparator.new(values)
    patterns = iteration_filter_values.range_patterns
    expected_pattern = { gte: @iteration_1_title, lte: "" }
    range_clause = iteration_filter_values.range_clause(@iterations, patterns)
    expected_clause = { gte: @iteration_1_start_date }

    assert_equal expected_pattern, patterns
    assert_equal expected_clause, range_clause
  end

  test "range less or equal than <=Iteration 2" do
    values = ["<=#{@iteration_2_title}"]
    iteration_filter_values = MemexProject::IterationRangeComparator.new(values)
    patterns = iteration_filter_values.range_patterns
    expected_pattern = { lte: @iteration_2_title }
    range_clause = iteration_filter_values.range_clause(@iterations, patterns)
    expected_clause = { lte: @iteration_2_start_date }

    assert_equal expected_pattern, patterns
    assert_equal expected_clause, range_clause
  end

  test "range less than *..Iteration 2" do
    values = ["*..#{@iteration_2_title}"]
    iteration_filter_values = MemexProject::IterationRangeComparator.new(values)
    patterns = iteration_filter_values.range_patterns
    expected_pattern = { gte: "", lte: @iteration_2_title }
    range_clause = iteration_filter_values.range_clause(@iterations, patterns)
    expected_clause = { lte: @iteration_2_start_date }

    assert_equal expected_pattern, patterns
    assert_equal expected_clause, range_clause
  end

  test "range greater than >Iteration 2" do
    values = [">#{@iteration_2_title}"]
    iteration_filter_values = MemexProject::IterationRangeComparator.new(values)
    patterns = iteration_filter_values.range_patterns
    expected_pattern = { gt: @iteration_2_title }
    range_clause = iteration_filter_values.range_clause(@iterations, patterns)
    expected_clause = { gt: @iteration_2_start_date }

    assert_equal expected_pattern, patterns
    assert_equal expected_clause, range_clause
  end

  test "range less than <Iteration 2" do
    values = ["<#{@iteration_2_title}"]
    iteration_filter_values = MemexProject::IterationRangeComparator.new(values)
    patterns = iteration_filter_values.range_patterns
    expected_pattern = { lt: @iteration_2_title }
    range_clause = iteration_filter_values.range_clause(@iterations, patterns)
    expected_clause = { lt: @iteration_2_start_date }

    assert_equal expected_pattern, patterns
    assert_equal expected_clause, range_clause
  end

  test "no range should return nil" do
    values = ["#{@iteration_1_title}"]
    iteration_filter_values = MemexProject::IterationRangeComparator.new(values)
    patterns = iteration_filter_values.range_patterns
    expected_pattern = {}
    range_clause = iteration_filter_values.range_clause(@iterations, patterns)

    assert_equal expected_pattern, patterns
    assert_nil range_clause
  end

  test "range pattern between macros" do
    values = ["@current..@current+1"]
    iteration_filter_values = MemexProject::IterationRangeComparator.new(values)
    patterns = iteration_filter_values.range_patterns
    expected_pattern = { gte: "@current", lte: "@current+1" }

    assert_equal expected_pattern, patterns
  end
end
