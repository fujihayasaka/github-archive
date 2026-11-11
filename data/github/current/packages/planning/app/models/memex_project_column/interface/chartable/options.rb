# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Chartable

  # Encapsulates options for querying Insights chart data from Elasticsearch via MemexProjectItemQuery.
  #
  # Possible options to query with xAxis Assignee asc (default) and Grouped by Status (desc)
  # yAxis default is an aggregated count of items
  #
  # {
  #   "xAxis": {
  #     "dataSource": {
  #       "field_object_or_id": 1062769,
  #       "order": "asc"
  #     },
  #     "groupBy": {
  #       "field_object_or_id": 841442
  #       "order": "desc"
  #     }
  #   },
  #   "yAxis": {
  #     "aggregate": {
  #       "operation": "count"
  #     }
  #   }
  # }
  class Options

    DATE_REGEX = /\d{4}-\d{2}-\d{2}/
    # After this many years, we switch to a weekly rather than daily interval for historical charts.
    MAX_YEARS_FOR_DAILY_INTERVAL = 5

    # There are no confirmed, practical use cases for 'avg', 'min', or 'max' in historical charts.
    # ~135 out of ~26,300 persisted historical charts (~1.7M charts total) have 'avg', 'min', or 'max'.
    # If a request is made for these oddballs, we'll revert to showing 'count' rather than raising an error.
    # See https://github.com/github/projects-platform/issues/2761 for more details.
    SUPPORTED_HISTORICAL_Y_AXIS_OPERATIONS = [
      MemexProjectChart::Operation::Count,
      MemexProjectChart::Operation::Sum
    ].freeze

    class InvalidYAxisAggregateOperation < ArgumentError
      sig { params(operation: T.untyped).void }
      def initialize(operation)
        values = MemexProjectChart::Operation.values.collect(&:serialize)
        super("'yAxis.aggregate.operation' has an invalid operation '#{operation}', expected: #{values.to_sentence(last_word_connector: ', or ')}")
      end
    end

    class XAxisDataSource < T::Struct
      const :field_object_or_id, T.any(String, Integer, MemexProjectColumn::Field::Base) # only "time" is a valid string for historical charts
      const :order, T.nilable(String)  # "asc" or "desc"
    end

    class XAxisGroupBy < T::Struct
      const :field_object_or_id, T.any(Integer, MemexProjectColumn::Field::Base)
      const :order, T.nilable(String)  # "asc" or "desc"
    end

    class XAxis < T::Struct
      const :data_source, XAxisDataSource
      const :group_by, T.nilable(XAxisGroupBy)
    end

    class YAxisAggregate < T::Struct
      const :operation, MemexProjectChart::Operation
      const :field_object_or_id, T.nilable(T.any(Integer, MemexProjectColumn::Field::Base))
    end

    class YAxis < T::Struct
      const :aggregate, YAxisAggregate
    end

    # Optional user-provided time options for historical charts, mirroring the existing MemexProjectChart configuruation.
    class Time < T::Struct
      const :period, String
      const :start_date, T.nilable(String)
      const :end_date, T.nilable(String)
    end

    class TimeRange < T::Struct
      const :start_date, Date
      const :end_date, Date
    end

    sig { returns(Options::XAxis) }
    attr_reader :x_axis

    # The x-axis field. This is nil for a historical chart.
    sig { returns(T.nilable(MemexProjectColumn::Field::Base)) }
    attr_reader :x_axis_field

    # The optional x-axis group by field.
    sig { returns(T.nilable(MemexProjectColumn::Field::Base)) }
    attr_reader :x_group_field

    sig { returns(T.nilable(Options::Time)) }
    attr_reader :time

    sig { returns(Options::YAxis) }
    attr_reader :y_axis

    # The optional, numeric field used for y-axis aggregations (sum, avg, min, max).
    sig { returns(T.nilable(MemexProjectColumn::Field::Base)) }
    attr_reader :y_axis_aggregate_field

    # The computed time range for a historical chart based on the provided time parameter, if not max.
    sig { returns(T.nilable(TimeRange)) }
    attr_reader :time_range

    # The computed time interval for a historical chart based on the provided time parameter, if not max.
    # This is "1d" for daily intervals and "1w" for weekly intervals.
    sig { returns(String) }
    attr_reader :time_interval

    # Returns the appropriate Elasticsearch date historgram calendar_interval "1d" or "1w".
    # For larger time ranges, we switch to a weekly interval.
    sig { params(start_date: Date, end_date: Date).returns(String) }
    def self.calculate_time_interval(start_date:, end_date:)
      start_date < end_date.years_ago(MAX_YEARS_FOR_DAILY_INTERVAL) ? "1w" : "1d"
    end

    # Returns a time range for a historical chart based on the provided dates.
    # Adjusts dates to start on Monday and end on Sunday if the interval is weekly "1w".
    # This ensures that the weekly date histogram bins are inclusive of data at the start and end weeks.
    sig { params(start_date: Date, end_date: Date, time_interval: String).returns(Options::TimeRange) }
    def self.create_time_range(start_date:, end_date:, time_interval:)
      if time_interval == "1w"
        start_date = start_date.prev_occurring(:monday) unless start_date.monday?
        end_date = end_date.next_occurring(:sunday) unless end_date.sunday?
      end
      TimeRange.new(start_date:, end_date:)
    end

    # Initializes options for querying Insights chart data from Elasticsearch via MemexProjectItemQuery.
    # Parameters mirror the relevant names/structure of the existing MemexProjectChart configuration JSON.
    #
    # @param x_axis The x-axis configuration options.
    # @param time The optional time configuratioan options for historical charts.  Defaults to the last 2 weeks.
    sig do
      params(
        x_axis: Options::XAxis,
        y_axis: T.nilable(Options::YAxis),
        time: T.nilable(Options::Time)
      )
      .void
    end
    def initialize(x_axis:, y_axis: nil, time: nil)
      @x_axis = x_axis

      y_axis ||= YAxis.new(
        aggregate: YAxisAggregate.new(
          operation: MemexProjectChart::Operation::Count,
        ),
      )
      @y_axis = T.let(y_axis, YAxis)

      # validate the y_axis field if requesting a numeric aggregation (sum, max, etc.) rather than the default item counts
      if @y_axis.aggregate.operation == MemexProjectChart::Operation::Count
        raise ArgumentError, "yAxis aggregate field cannot be provided when 'yAxis.aggregate.operation' is 'count'" if @y_axis.aggregate.field_object_or_id.present?
      elsif @y_axis.aggregate.field_object_or_id.present?
        field = @y_axis.aggregate.field_object_or_id
        unless field.is_a?(MemexProjectColumn::Field::Base)
          field = MemexProjectColumn.find_by(id: field)&.to_field
        end
        raise ArgumentError, "Could not retrieve y_axis aggregate field with ID #{field}" unless field.present?
        raise ArgumentError, "yAxis aggregate field must be a numeric field" unless field.class.summable?
        @y_axis_aggregate_field = T.let(field, T.nilable(MemexProjectColumn::Field::Base))
      else
        raise ArgumentError, "yAxis aggregate field must be provided when 'yAxis.aggregate.operation' is 'sum', 'avg', 'min', or 'max'"
      end

      @time_interval = T.let("1d", String)

      if historical_chart?
        set_time_range(time)
        # Revert to returning 'count' for previously saved historical charts with deprecated 'avg', 'min', or 'max' operations.
        unless SUPPORTED_HISTORICAL_Y_AXIS_OPERATIONS.include?(@y_axis.aggregate.operation)
          @y_axis = YAxis.new(aggregate: YAxisAggregate.new(operation: MemexProjectChart::Operation::Count))
          @y_axis_aggregate_field = nil
        end
      else
        # validate x_axis fields for a current state chart
        field = x_axis.data_source.field_object_or_id
        unless field.is_a?(MemexProjectColumn::Field::Base)
          field = MemexProjectColumn.find_by(id: field)&.to_field
        end
        raise ArgumentError, "Could not retrieve x_axis field with ID #{field}" unless field.present?
        @x_axis_field = T.let(field, MemexProjectColumn::Field::Base)

        field = x_axis.group_by&.field_object_or_id
        if field.present?
          unless field.is_a?(MemexProjectColumn::Field::Base)
            field = MemexProjectColumn.find_by(id: field)&.to_field
          end
          raise ArgumentError, "Could not retrieve group_by field with ID #{field}" unless field.present?
          @x_group_field = T.let(field, MemexProjectColumn::Field::Base)
        end
      end
    end

    # Returns true if this is a historical chart with "time" as the x-axis.
    sig { returns(T::Boolean) }
    def historical_chart?
      x_axis.data_source.field_object_or_id == "time"
    end

    # Validates and set the time_range dates and interval for a historical chart based on the provided time parameter.
    sig { params(time: T.nilable(Options::Time)).void }
    private def set_time_range(time)
      @time = T.let(time.presence, T.nilable(Options::Time))
      @time = @time || Time.new(period: MemexProjectChart::DEFAULT_PERIOD)
      return if @time.period == "max"

      end_date = ::Time.now.utc.to_date
      raise ArgumentError, "'time.period' must be one of: #{MemexProjectChart::TIME_PERIODS.join(", ")}" unless MemexProjectChart::TIME_PERIODS.include?(@time.period)

      case @time.period
      when "2W"
        start_date = end_date.prev_day(14)
      when "1M"
        start_date = end_date.prev_month(1)
      when "3M"
        start_date = end_date.prev_month(3)
      when "custom"
        start_date = validate_date(date_string: @time.start_date, field_name: "time.startDate")
        end_date = validate_date(date_string: @time.end_date, field_name: "time.endDate")
        raise ArgumentError, "time.startDate cannot be later than time.endDate" if start_date > end_date
        raise ArgumentError, "time range cannot be greater than 50 years" if start_date < end_date.years_ago(50)
      else
        raise ArgumentError, "Unknown time period: #{@time.period}"
      end

      @time_interval = self.class.calculate_time_interval(start_date:, end_date:)
      @time_range = T.let(self.class.create_time_range(start_date:, end_date:, time_interval: @time_interval), T.nilable(Options::TimeRange))
    end

    sig { params(date_string: T.nilable(String), field_name: String).returns(Date) }
    private def validate_date(date_string:, field_name:)
      raise ArgumentError, "#{field_name} must be in the format YYYY-MM-DD"  unless date_string&.match(/\d{4}-\d{2}-\d{2}/)
      begin
        Date.parse(date_string)
      rescue ArgumentError
        raise ArgumentError, "#{field_name} must be a valid date"
      end
    end
  end
end
