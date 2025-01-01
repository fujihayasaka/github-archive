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

    @iteration_field_with_unusual_titles = create(
      :iteration_memex_column,
      name: "Funny iteration names",
      memex_project: @memex,
      settings: {
        configuration: {
          start_day: 1,
          duration: 14,
          iterations: [
              "Iteration 1.1",
              "Iteration 1.2",
              "Iteration 2.*",
              "Platform's special iteration",
            ].each_with_index.map do |title, index|
              {
                title:,
                start_date: "#{Date.today + index.weeks}",
                duration: 14
              }
            end
        }
      }
    ).to_field
  end

  def assert_matches(test:, query:, results:, negated: false, field: @iteration_field)
    comparator = MemexProject::IterationComparator.new(Array(query), field:, negated:)
    actual_matches = field.settings_all_iterations.filter_map { comparator.matches?(_1) && _1 }
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
      results: @iteration_field.settings_all_iterations - [@iterations.first]
    )
    assert_matches(
      test: "negation with multiple values",
      query: [@iterations.first["title"], @iterations.second["title"]],
      negated: true,
      results: @iteration_field.settings_all_iterations - [@iterations.first, @iterations.second]
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

  test "filter formats with extrapolation and date error handling" do
    assert_matches(
      test: "nonexistent title",
      query: "NonExistentIteration",
      results: [],
    )
    assert_matches(
      test: "greater than (> nonexistent Iteration)",
      query: ">NonExistentIteration",
      results: [],
    )
    assert_matches(
      test: "less than (< nonexistent Iteration)",
      query: "<NonExistentIteration",
      results: [],
    )
    assert_matches(
      test: "greater than or equal to(>= nonexistent Iteration)",
      query: "NonExistentIteration",
      results: [],
    )
    assert_matches(
      test: "greater than or equal to, range style (nonexistent Iteration..*)",
      query: "NonExistentIteration..*",
      results: [],
    )
    assert_matches(
      test: "less than or equal to(<= nonexistent Iteration)",
      query: "<=NonExistentIteration",
      results: [],
    )
    assert_matches(
      test: "less than or equal to, range style (*..nonexistent Iteration)",
      query: "*..NonExistentIteration",
      results: [],
    )
    assert_matches(
      test: "between (nonexistent Iteration x..nonexistent Iteration y)",
      query: "NonExistentIterationX..NonExistentIterationY",
      results: [],
    )
    assert_matches(
      test: "macro addition for a nonexistent iteration (@current+10)",
      query: "@current+10",
      results: [],
    )
    assert_matches(
      test: "macro subtraction for a nonexistent iteration (@current-10)",
      query: "@current-10",
      results: [],
    )
    assert_matches(
      test: "macro addition with range exceeding actual range of iterations (@previous..@next+20)",
      query: "@previous..@next+20",
      results: [@completed_iterations.last] + @iterations,
    )
    assert_matches(
      test: "macro subtraction with range exceeding actual range of iterations (@previous-10..@next+2)",
      query: "@previous-10..@next+2",
      results: @completed_iterations + @iterations[0..3],
    )
    assert_matches(
      test: "negation with nonexistent title",
      query: "NonExistentIteration",
      negated: true,
      results: @iteration_field.settings_all_iterations
    )
    assert_matches(
      test: "negation with multiple values and one nonexistent title",
      query: [@iterations.first["title"], @iterations.second["title"], "NonExistentIteration"],
      negated: true,
      results: @iteration_field.settings_all_iterations - [@iterations.first, @iterations.second]
    )
    assert_matches(
      test: "multiple values with one nonexistent title",
      query: ["NonExistentIteration", "@previous-2..@previous"],
      # Note that order is inverted here because we're sorting by start date
      results: @completed_iterations.last(3)
    )
  end

  test "macro subtraction with nonexistent @current iteration" do
    memex = create(:memex_project)
    iteration_field = create(:iteration_memex_column_with_completed_iterations, upcoming: 0, completed: 5, memex_project: memex).to_field
    iterations = iteration_field.settings["configuration"]["iterations"].sort_by { _1["start_date"] }
    completed_iterations = iteration_field.settings_completed_iterations.sort_by { _1["start_date"] }

    # assert only completed iterations exist, no current iteration.
    assert_equal 0, iterations.length
    assert_equal 5, completed_iterations.length

    query = "<@current-2"
    expected_results = completed_iterations.first(3)

    comparator = MemexProject::IterationComparator.new(Array(query), field: iteration_field)
    actual_matches = completed_iterations.filter_map { comparator.matches?(_1) && _1 }
    assert_equal expected_results, actual_matches
  end

  test "exact title filtering when title contains a single dot" do
    expected_results = @iteration_field_with_unusual_titles.settings["configuration"]["iterations"].sort_by { _1["start_date"] }[0...2]
    refute_empty expected_results

    assert_matches(
      test: "exact title with a single dot in it",
      query: ["Iteration 1.1", "Iteration 1.2"],
      results: expected_results,
      field: @iteration_field_with_unusual_titles
    )
  end

  test "exact title filtering when title contains an apostrophe" do
    all_iterations = @iteration_field_with_unusual_titles.settings["configuration"]["iterations"].sort_by { _1["start_date"] }
    expected_results = [all_iterations[0], all_iterations[3]]
    refute_empty expected_results

    assert_matches(
      test: "exact title with an apostrophe in it",
      query: ["Iteration 1.1", "Platform's special iteration"],
      results: expected_results,
      field: @iteration_field_with_unusual_titles
    )
  end

  test "exact title filtering when title contains an asterisk" do
    all_iterations = @iteration_field_with_unusual_titles.settings["configuration"]["iterations"].sort_by { _1["start_date"] }
    expected_results = [all_iterations[0], all_iterations[2]]
    refute_empty expected_results

    assert_matches(
      test: "exact title with an asterisk in it",
      query: ["Iteration 1.1", "Iteration 2.*"],
      results: expected_results,
      field: @iteration_field_with_unusual_titles
    )
  end

  test "range filtering with optionally quoted iteration titles" do
    iterations = @iteration_field_with_unusual_titles.settings["configuration"]["iterations"].sort_by { _1["start_date"] }
    expected_results = iterations[0...3]
    refute_empty expected_results

    # For these iteration titles, we should receive the same results regardless of whether the titles
    # are quoted, because the titles do not create ambiguity with the range operator.
    assert_matches(
      test: "range filtering with quoted iteration names",
      query: ["Iteration 1.1..Iteration 2.*"],
      results: expected_results,
      field: @iteration_field_with_unusual_titles
    )
    assert_matches(
      test: "range filtering with unquoted but unambiguous iteration names",
      query: ['"Iteration 1.1".."Iteration 2.*"'],
      results: expected_results,
      field: @iteration_field_with_unusual_titles
    )
  end

  test "filtering where quoting iteration titles is necessary to remove ambiguity" do
    field = create(
      :iteration_memex_column,
      name: "Leading and trailing dots",
      memex_project: @memex,
      settings: {
        configuration: {
          start_day: 1,
          duration: 14,
          iterations: [
              "Iteration 1...",
              "...Iteration 2...",
              "...Iteration 3",
            ].each_with_index.map do |title, index|
              {
                title:,
                start_date: "#{Date.today + index.weeks}",
                duration: 14
              }
            end
        }
      }
    ).to_field

    iterations = field.settings["configuration"]["iterations"].sort_by { _1["start_date"] }

    # In these case the user must quote the iteration titles to resolve the ambiguity as to
    # where the range operator appears (if at all).
    assert_matches(
      test: "single value filtering with necessary quoting",
      query: ['"...Iteration 2..."'],
      results: [iterations[1]],
      field:
    )
    assert_matches(
      test: "multiple value filtering with necessary quoting",
      query: ['"Iteration 1..."', '"...Iteration 3"'],
      results: [iterations[0], iterations[2]],
      field:
    )
    assert_matches(
      test: "range filtering with necessary quoting",
      query: ['"...Iteration 2...".."...Iteration 3"'],
      results: iterations[1...3],
      field:
    )
  end
end
