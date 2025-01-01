# typed: true
# frozen_string_literal: true

require "test_helper"

module MemexProjectColumn::Interface::Chartable
  class OptionsTest < GitHub::TestCase

    fixtures do
      @memex = create(:memex_project)
      @assignee_column = @memex.columns.find(&:assignees?)
      @status_column = @memex.status_column
      @numeric_column = create(:number_memex_column, memex_project: @memex, name: "estimate")
    end

    context "#initialize" do
      test "sets default yAxis if not provided" do
        options = Options.new(
          x_axis: Options::XAxis.new(
            data_source: Options::XAxisDataSource.new(
              field_object_or_id: @status_column.id,
            ),
            group_by: Options::XAxisGroupBy.new(
              field_object_or_id: @assignee_column.id,
            ),
          ),
        )

        assert_kind_of Options::YAxis, options.y_axis, "expected yAxis to be an instance of Options::YAxis"
        assert_equal MemexProjectChart::Operation::Count, T.must(options.y_axis).aggregate.operation, "expected yAxis.aggregate.operation to default to 'count'"
        assert_nil T.must(options.y_axis).aggregate.field_object_or_id, "expected yAxis.aggregagte.field_object_or_id to default to nil"
      end
    end

    context "#y_axis=" do
      test "can be set by field Ids" do
        # This verifies that all Options field_object_or_id properties can be set by field Ids
        aggregate = Chartable::Options::YAxisAggregate.new(
          operation: MemexProjectChart::Operation::Sum,
          field_object_or_id: @numeric_column.id,
        )
        options = Options.new(
          x_axis: Options::XAxis.new(
            data_source: Options::XAxisDataSource.new(
              field_object_or_id: @status_column.id,
            ),
            group_by: Options::XAxisGroupBy.new(
              field_object_or_id: @assignee_column.id,
            ),
          ),
          y_axis: Chartable::Options::YAxis.new(
            aggregate:,
          ),
        )

        assert_kind_of Chartable::Options::YAxis, options.y_axis, "expected options to be an instance of YAxis"
      end

      test "can be set by field objects" do
        # This verifies that all Options field_object_or_id properties can be set by field objects
        aggregate = Chartable::Options::YAxisAggregate.new(
          operation: MemexProjectChart::Operation::Sum,
          field_object_or_id: @numeric_column.to_field,
        )
        options = Options.new(
          x_axis: Options::XAxis.new(
            data_source: Options::XAxisDataSource.new(
              field_object_or_id: @status_column.to_field,
            ),
            group_by: Options::XAxisGroupBy.new(
              field_object_or_id: @assignee_column.to_field,
            ),
          ),
          y_axis: Chartable::Options::YAxis.new(
            aggregate:,
          ),
        )

        assert_kind_of Chartable::Options::YAxis, options.y_axis, "expected options to be an instance of YAxis"
      end

      test "count operation must not have field_object_or_id" do
        aggregate = Chartable::Options::YAxisAggregate.new(
          operation: MemexProjectChart::Operation::Count,
          field_object_or_id: @numeric_column.id,
        )
        exception = assert_raises ArgumentError do
          Options.new(
            x_axis: Options::XAxis.new(
              data_source: Options::XAxisDataSource.new(
                field_object_or_id: @status_column.id,
              ),
              group_by: Options::XAxisGroupBy.new(
                field_object_or_id: @assignee_column.id,
              ),
            ),
            y_axis: Chartable::Options::YAxis.new(
              aggregate:,
            ),
          )
        end

        assert_equal "yAxis aggregate field cannot be provided when 'yAxis.aggregate.operation' is 'count'", exception.message
      end

      test "sum operation must have field_object_or_id" do
        aggregate = Chartable::Options::YAxisAggregate.new(
          operation: MemexProjectChart::Operation::Sum,
        )
        exception = assert_raises ArgumentError do
          Options.new(
            x_axis: Options::XAxis.new(
              data_source: Options::XAxisDataSource.new(
                field_object_or_id: @status_column.id,
              ),
              group_by: Options::XAxisGroupBy.new(
                field_object_or_id: @assignee_column.id,
              ),
            ),
            y_axis: Chartable::Options::YAxis.new(
              aggregate:,
            ),
          )
        end

        assert_equal "yAxis aggregate field must be provided when 'yAxis.aggregate.operation' is 'sum', 'avg', 'min', or 'max'", exception.message
      end

      test "avg operation must have field_object_or_id" do
        aggregate = Chartable::Options::YAxisAggregate.new(
          operation: MemexProjectChart::Operation::Avg,
        )
        exception = assert_raises ArgumentError do
          Options.new(
            x_axis: Options::XAxis.new(
              data_source: Options::XAxisDataSource.new(
                field_object_or_id: @status_column.id,
              ),
              group_by: Options::XAxisGroupBy.new(
                field_object_or_id: @assignee_column.id,
              ),
            ),
            y_axis: Chartable::Options::YAxis.new(
              aggregate:,
            ),
          )
        end

        assert_equal "yAxis aggregate field must be provided when 'yAxis.aggregate.operation' is 'sum', 'avg', 'min', or 'max'", exception.message
      end

      test "max operation must have field_object_or_id" do
        aggregate = Chartable::Options::YAxisAggregate.new(
          operation: MemexProjectChart::Operation::Max,
        )
        exception = assert_raises ArgumentError do
          Options.new(
            x_axis: Options::XAxis.new(
              data_source: Options::XAxisDataSource.new(
                field_object_or_id: @status_column.id,
              ),
              group_by: Options::XAxisGroupBy.new(
                field_object_or_id: @assignee_column.id,
              ),
            ),
            y_axis: Chartable::Options::YAxis.new(
              aggregate:,
            ),
          )
        end

        assert_equal "yAxis aggregate field must be provided when 'yAxis.aggregate.operation' is 'sum', 'avg', 'min', or 'max'", exception.message
      end

      test "min operation must have field_object_or_id" do
        aggregate = Chartable::Options::YAxisAggregate.new(
          operation: MemexProjectChart::Operation::Min,
        )
        exception = assert_raises ArgumentError do
          Options.new(
            x_axis: Options::XAxis.new(
              data_source: Options::XAxisDataSource.new(
                field_object_or_id: @status_column.id,
              ),
              group_by: Options::XAxisGroupBy.new(
                field_object_or_id: @assignee_column.id,
              ),
            ),
            y_axis: Chartable::Options::YAxis.new(
              aggregate:,
            ),
          )
        end

        assert_equal "yAxis aggregate field must be provided when 'yAxis.aggregate.operation' is 'sum', 'avg', 'min', or 'max'", exception.message
      end

      test "aggregate operation field_object_or_id must be a numeric field" do
        aggregate = Chartable::Options::YAxisAggregate.new(
          operation: MemexProjectChart::Operation::Sum,
          field_object_or_id: @status_column.id,
        )
        exception = assert_raises ArgumentError do
          Options.new(
            x_axis: Options::XAxis.new(
              data_source: Options::XAxisDataSource.new(
                field_object_or_id: @status_column.id,
              ),
              group_by: Options::XAxisGroupBy.new(
                field_object_or_id: @assignee_column.id,
              ),
            ),
            y_axis: Chartable::Options::YAxis.new(
              aggregate:,
            ),
          )
        end

        assert_equal "yAxis aggregate field must be a numeric field", exception.message
      end
    end

    context "time" do
      test "calculates a time interval of 1 day for a range less than 5 years" do
        end_date = Date.new
        start_date = end_date.years_ago(5).days_ago(-1)
        interval = Options.calculate_time_interval(start_date:, end_date:)

        assert_equal "1d", interval
      end

      test "calculates a time interval of 1 week for a range greater than 5 years" do
        end_date = Date.new
        start_date = end_date.years_ago(5).days_ago(1)
        interval = Options.calculate_time_interval(start_date:, end_date:)

        assert_equal "1w", interval
      end

      test "creates a time range with the given start and end dates if daily interval" do
        end_date = Date.new(2025, 1, 15) # Wednesday January 15, 2025
        start_date = end_date.days_ago(1) # Tuesday January 14, 2025
        time_range = Options.create_time_range(start_date:, end_date:, time_interval: "1d")

        assert_equal start_date, time_range.start_date
        assert_equal end_date, time_range.end_date
      end

      test "creates a time range with with the preceding Monday and following Sunday if weekly interval" do
        end_date = Date.new(2025, 1, 15) # Wednesday January 15, 2025
        start_date = end_date.days_ago(1) # Tuesday January 14, 2025
        time_range = Options.create_time_range(start_date:, end_date:, time_interval: "1w")

        assert_equal start_date.prev_occurring(:monday), time_range.start_date
        assert_equal end_date.next_occurring(:sunday), time_range.end_date
      end
    end
  end
end
