# typed: true
# frozen_string_literal: true

require "test_helper"

class IterationComparatorTest < GitHub::TestCase
  include MemexHelpers

  fixtures do
    @memex = create(:memex_project)
    @iteration_field = create(:iteration_memex_column_with_completed_iterations, upcoming: 5, completed: 5, memex_project: @memex).to_field
    @iterations = @iteration_field.settings["configuration"]["iterations"].sort_by { _1["start_date"] }
    @completed_iterations = @iteration_field.settings_completed_iterations.sort_by { _1["start_date"] }
    @all_iterations = @iteration_field.settings_all_iterations
  end

  def assert_matches(test:, query:, results:, negated: false)
    comparator = MemexProject::IterationComparator.new(Array(query), field: @iteration_field, negated:)
    actual_matches = @all_iterations.filter_map { comparator.matches?(_1) && _1 }
    assert_equal results, actual_matches, "#{test} failed"
  end

  test "all filter formats" do
    assert_matches(
      test: "exact title",
      query: @iterations.second["title"],
      results: [@iterations.second],
    )
    assert_matches(
      test: "greater than (> Iteration)",
      query: ">#{@iterations.first["title"]}",
      results: @iterations[1..4],
    )
    assert_matches(
      test: "less than (< Iteration)",
      query: "<#{@iterations.second["title"]}",
      results: @completed_iterations + [@iterations.first],
    )
    assert_matches(
      test: "greater than or equal to(>= Iteration)",
      query: ">=#{@iterations.first["title"]}",
      results: @iterations[0..4],
    )
    assert_matches(
      test: "greater than or equal to, range style (Iteration..*)",
      query: "#{@iterations.first["title"]}..*",
      results: @iterations[0..4],
    )
    assert_matches(
      test: "less than or equal to(<= Iteration)",
      query: "<=#{@iterations.second["title"]}",
      results: @completed_iterations + @iterations[0..1],
    )
    assert_matches(
      test: "less than or equal to, range style (*..Iteration)",
      query: "*..#{@iterations.second["title"]}",
      results: @completed_iterations + @iterations[0..1],
    )
    assert_matches(
      test: "between (Iteration x..Iteration y)",
      query: "#{@iterations.first["title"]}..#{@iterations.third["title"]}",
      results: [@iterations.first, @iterations.second, @iterations.third],
    )
    assert_matches(
      test: "macros (@current)",
      query: "@current",
      results: [@iterations.first],
    )
    assert_matches(
      test: "macros (@previous..@next)",
      query: "@previous..@next",
      results: [@completed_iterations.last] + @iterations[0..1],
    )
    assert_matches(
      test: "macro addition (@current+1)",
      query: "@current+1",
      results: [@iterations.second],
    )
    assert_matches(
      test: "macro subtraction (@current-1)",
      query: "@current-1",
      results: [@completed_iterations.last],
    )
    assert_matches(
      test: "macro addition with range (@previous..@next+2)",
      query: "@previous..@next+2",
      results: [@completed_iterations.last] + @iterations[0..3],
    )
    assert_matches(
      test: "combination title + macro + range + math (Iteration..@next+2)",
      query: "#{@completed_iterations.last["title"]}..@next+2",
      results: [@completed_iterations.last] + @iterations[0..3],
    )
    assert_matches(
      test: "negation",
      query: @iterations.first["title"],
      negated: true,
      results: @all_iterations - [@iterations.first]
    )
    assert_matches(
      test: "multiple values",
      query: [@iterations.last["title"], "@previous-2..@previous"],
      # Note that order is inverted here because we're sorting by start date
      results: @completed_iterations.last(3) + [@iterations.last]
    )
    assert_matches(
      test: "single quoted values",
      query: ["'#{@iterations.first["title"]}'"],
      results: [@iterations.first]
    )
    assert_matches(
      test: "double quoted values",
      query: ["\"#{@iterations.first["title"]}\""],
      results: [@iterations.first]
    )
  end
end
