# typed: true
# frozen_string_literal: true

require "test_helper"

class FilterValueResolverTest < GitHub::TestCase
  fixtures do
    @iteration_with_completions_column = create(:iteration_memex_column_with_completed_iterations, upcoming: 5, completed: 5)
    @iteration_with_only_completions   = create(:iteration_memex_column_with_completed_iterations, upcoming: 0, completed: 5)
    @no_iterations                     = create(:iteration_memex_column_with_completed_iterations, upcoming: 0, completed: 0)
    @iteration_column_completed        = create(:iteration_memex_column_with_completed)
    @iteration_column                  = create(:iteration_memex_column)
    @date_column                       = create(:date_memex_column)
    @single_select_column              = create(:single_select_memex_column)
  end

  setup do
    # Use this deterministic time for testing.
    @time = Time.parse("2010-01-01T00:00:00Z")

    # time is passed into the constructor in order test as today is the current iteration.
    # This could also be achieved using Timecop but hopefully this enhances the de-coupling between
    # Time and our business classes.  It will also safely default to Time.current if not provided.
    @iteration_with_completions_resolver = MemexProject::FilterValueResolver.new(
      @iteration_with_completions_column,
      time: Time.parse(@iteration_with_completions_column.settings_iterations.first["start_date"])
    )

    @iteration_with_completions_start_date_resolver = MemexProject::FilterValueResolver.new(
      @iteration_with_completions_column,
      iteration_key: "start_date",
      time: Time.parse(@iteration_with_completions_column.settings_iterations.first["start_date"]),
    )

    @iteration_with_only_completions_start_date_resolver = MemexProject::FilterValueResolver.new(
      @iteration_with_only_completions,
      iteration_key: "start_date",
    )

    @date_resolver = MemexProject::FilterValueResolver.new(
      @date_column,
      time: time
    )

    @single_select_resolver = MemexProject::FilterValueResolver.new(
      @single_select_column,
      time: time
    )

    @current_is_first_iteration_resolver = MemexProject::FilterValueResolver.new(
      @iteration_column,
      iteration_key: "start_date"
    )

    @current_is_last_iteration_resolver = MemexProject::FilterValueResolver.new(
      @iteration_column_completed,
      iteration_key: "start_date"
    )

    @no_iterations_resolver = MemexProject::FilterValueResolver.new(
      @no_iterations,
      iteration_key: "start_date"
    )
  end

  context "for an iteration column" do
    test "macro-replacement is case-insensitive" do
      filter_values          = ["@cUrReNt"]
      expected_filter_values = [@iteration_with_completions_column.settings_iterations.first["id"]]
      actual_filter_values   = @iteration_with_completions_resolver.resolve(filter_values)

      assert_equal expected_filter_values, actual_filter_values
    end

    test "replaces @current with current iteration's ID" do
      filter_values          = ["@current"]
      expected_filter_values = [@iteration_with_completions_column.settings_iterations.first["id"]]
      actual_filter_values   = @iteration_with_completions_resolver.resolve(filter_values)

      assert_equal expected_filter_values, actual_filter_values
    end

    test "replaces @current+4 with the ID of the fourth-next iteration" do
      filter_values          = ["@current+4"]
      expected_filter_values = [@iteration_with_completions_column.settings_iterations[4]["id"]]
      actual_filter_values   = @iteration_with_completions_resolver.resolve(filter_values)

      assert_equal expected_filter_values, actual_filter_values
    end

    test "replaces @current-5 with the ID of the fifth-previous iteration" do
      filter_values          = ["@current-5"]
      expected_filter_values = [@iteration_with_completions_column.settings_completed_iterations[4]["id"]]
      actual_filter_values   = @iteration_with_completions_resolver.resolve(filter_values)

      assert_equal expected_filter_values, actual_filter_values
    end

    test "replaces @previous with previous iteration's ID" do
      filter_values          = ["@previous"]
      expected_filter_values = [@iteration_with_completions_column.settings_completed_iterations.first["id"]]
      actual_filter_values   = @iteration_with_completions_resolver.resolve(filter_values)

      assert_equal expected_filter_values, actual_filter_values
    end

    test "replaces @next with the next iteration's ID" do
      filter_values          = ["@next"]
      expected_filter_values = [@iteration_with_completions_column.settings_iterations.second["id"]]
      actual_filter_values   = @iteration_with_completions_resolver.resolve(filter_values)

      assert_equal expected_filter_values, actual_filter_values
    end

    test "returns @<macro> filter value if no relative iteration exists" do
      filter_values        = ["@current", "@previous", "@next"]
      actual_filter_values = @no_iterations_resolver.resolve(filter_values)

      assert_same_elements filter_values, actual_filter_values
    end

    context "range" do
      test "@current..@current+1 returns start_dates when @current is the first iteration" do
        actual_filter_values = @current_is_first_iteration_resolver.resolve(["@current", "@current+1"])

        current_start_date = @iteration_column.settings_iterations.first["start_date"]
        next_start_date = @iteration_column.settings_iterations.second["start_date"]

        assert_equal [current_start_date, next_start_date], actual_filter_values
      end

      test "@current..@current+2 returns start_dates when @current is between completed and upcoming" do
        actual_filter_values = @iteration_with_completions_start_date_resolver.resolve(["@current", "@current+2"])

        current_start_date = @iteration_with_completions_column.settings_iterations.first["start_date"]
        third_start_date = @iteration_with_completions_column.settings_iterations.third["start_date"]

        assert_equal [current_start_date, third_start_date], actual_filter_values
      end

      test "@current-2..@current returns start_dates when @current is between completed and upcoming" do
        actual_filter_values = @iteration_with_completions_start_date_resolver.resolve(["@current-2", "@current"])

        completed_start_date = @iteration_with_completions_column.settings_completed_iterations.second["start_date"]
        current_start_date = @iteration_with_completions_column.settings_iterations.first["start_date"]

        assert_equal [completed_start_date, current_start_date], actual_filter_values

      end

      test "@current-1..@current returns start_dates when @current is the last iteration" do
        actual_filter_values = @current_is_last_iteration_resolver.resolve(["@current-1", "@current"])

        previous_start_date = @iteration_column_completed.settings_completed_iterations.first["start_date"]
        current_start_date = @iteration_column_completed.settings_iterations.last["start_date"]

        assert_equal [previous_start_date, current_start_date], actual_filter_values
      end

      test "@previous+1 returns current iteration" do
        actual_filter_values = @current_is_last_iteration_resolver.resolve(["@previous+1"])
        current_start_date = @iteration_column_completed.settings_iterations.last["start_date"]
        assert_equal [current_start_date], actual_filter_values
      end

      test "@next+1 returns the third iteration when current is the first non-completed" do
        actual_filter_values = @iteration_with_completions_start_date_resolver.resolve(["@next+1"])
        expected_start_date = @iteration_with_completions_column.settings_iterations.third["start_date"]
        assert_equal [expected_start_date], actual_filter_values
      end

      test "@current..@current+10 returns current start_date and placeholder date after the last iteration" do
        actual_filter_values = @iteration_with_completions_start_date_resolver.resolve(["@current", "@current+10"])

        current_start_date = @iteration_with_completions_column.settings_iterations.first["start_date"]
        last_iteration = @iteration_with_completions_column.settings_iterations.last
        last_placeholder_date = (last_iteration["start_date"].to_date + last_iteration["duration"].to_i).to_s

        assert_equal [current_start_date, last_placeholder_date], actual_filter_values
      end

      test "@current-10..@current returns the placeholder date before the first iteration and current start_date" do
        actual_filter_values = @iteration_with_completions_start_date_resolver.resolve(["@current-10", "@current"])

        current_start_date = @iteration_with_completions_column.settings_iterations.first["start_date"]
        first_iteration = @iteration_with_completions_column.settings_completed_iterations.sort_by { |i| i["start_date"] }.first
        first_placeholder_date = (first_iteration["start_date"].to_date - 1).to_s

        assert_equal [first_placeholder_date, current_start_date], actual_filter_values
      end

      test "@current-10..@current+10 returns the placeholder dates before and after all iterations" do
        actual_filter_values = @iteration_with_completions_start_date_resolver.resolve(["@current-10", "@current+10"])

        current_start_date = @iteration_with_completions_column.settings_iterations.first["start_date"]
        first_iteration = @iteration_with_completions_column.settings_completed_iterations.sort_by { |i| i["start_date"] }.first
        first_placeholder_date = (first_iteration["start_date"].to_date - 1).to_s
        last_iteration = @iteration_with_completions_column.settings_iterations.last
        last_placeholder_date = (last_iteration["start_date"].to_date + last_iteration["duration"].to_i).to_s

        assert_equal [first_placeholder_date, last_placeholder_date], actual_filter_values
      end

      test "@current returns a placeholder date greater than completed iterations when there is no current iteration" do
        actual_filter_values = @iteration_with_only_completions_start_date_resolver.resolve(["@current"])

        last_completed_iteration = @iteration_with_only_completions.settings_completed_iterations.sort_by { |i| i["start_date"] }.last

        assert_equal 0, @iteration_with_only_completions.settings_iterations.length
        assert_equal 1, actual_filter_values.length
        assert actual_filter_values[0].to_date > last_completed_iteration["start_date"].to_date
      end

      test "Named iterations resolve to their start dates" do
        previous = @iteration_with_completions_column.settings_completed_iterations.first
        current = @iteration_with_completions_column.settings_iterations.last
        actual_filter_values = MemexProject::FilterValueResolver.new(@iteration_with_completions_column, iteration_key: "start_date")
          .resolve([previous["title"], current["title"]])
        assert_equal [previous["start_date"], current["start_date"]], actual_filter_values
      end
    end
  end

  context "for a date column" do
    test "macro-replacement is case-insensitive" do
      filter_values          = ["@ToDaY"]
      expected_filter_values = [@time.to_date.to_s]
      actual_filter_values   = @date_resolver.resolve(filter_values)

      assert_equal expected_filter_values, actual_filter_values
    end

    test "replaces @today with current date" do
      filter_values          = ["@today"]
      expected_filter_values = [@time.to_date.to_s]
      actual_filter_values   = @date_resolver.resolve(filter_values)

      assert_equal expected_filter_values, actual_filter_values
    end
  end

  context "for a single-select column" do
    test "it replaces values with option ids" do
      filter_values          = %w[small medium large]
      expected_filter_values = %w[aaaaaaaa bbbbbbbb cccccccc]
      actual_filter_values   = @single_select_resolver.resolve(filter_values)

      assert_equal expected_filter_values, actual_filter_values
    end

    test "options not matched by name get filtered out" do
      filter_values          = %w[i-dont-exist-as-an-option i-dont-either]
      expected_filter_values = []
      actual_filter_values   = @single_select_resolver.resolve(filter_values)

      assert_equal expected_filter_values, actual_filter_values
    end
  end
end
