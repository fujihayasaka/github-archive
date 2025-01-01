# typed: strict
# frozen_string_literal: true

# This module separates historical chart class methods from the main MemexProjectColumn::Interface::Chartable interface.
#
# Rather than including this module directly, consumers will inherit the Chartable interface via
# `MemexProjectColumn::Field::Base`, which is the base class for all fields supported by GitHub Projects.
module MemexProjectColumn::Interface::Chartable::HistoricalChart
  ElasticsearchRequest = Elastomer::Interfaces::Api::Search::Request
  Chartable = MemexProjectColumn::Interface::Chartable
  Options = Chartable::Options
  ChartData = Chartable::ChartData

  # Returns the Elasticsearch aggregation fragment for historical chart data.
  # This is a special case for time-based historical charts that require multiple date_histogram aggregations.
  sig { params(options: Options).returns(ElasticsearchRequest::Aggregation::Collection) }
  def self.historical_chart_fragment(options:)
    start_date = options.time_range&.start_date
    y_axis_aggregation = options.y_axis_aggregate_field&.build_y_axis_aggregation(options.y_axis.aggregate.operation)
    initial_open_agg = self.chart_open_before_time_range_aggregation(start_date:, y_axis_aggregation:) if start_date.present?

    date_histograms = [
      self.chart_x_axis_created_aggregation(options:, y_axis_aggregation:),
      self.chart_x_axis_issue_closed_aggregation(options:, y_axis_aggregation:),
      self.chart_x_axis_pr_closed_aggregation(options:, y_axis_aggregation:)
    ]

    ElasticsearchRequest::Aggregation::Collection.new(([initial_open_agg] + date_histograms).compact)
  end

  # Returns the historical chart data from the Elasticsearch aggregation results.
  # This is a special case for time-based historical charts rather than charting field values.
  sig { params(aggregation_results: T::Hash[T.untyped, T.untyped], total_hits: Integer, options: Options).returns(ChartData) }
  def self.historical_chart_data(aggregation_results:, total_hits:, options:)
    date_values = build_historical_chart_date_values(aggregation_results:, options:)
    chart_data = build_historical_chart_data(aggregation_results:, date_values:, options:, total_hits:)
    adjust_historical_time_interval(chart_data:, options:, total_hits:)
  end

  # Returns the Elasticsearch aggregation fragment for determining the initial open item count
  # if a start_date is provided for the query.
  sig do
    params(
      start_date: Date,
      y_axis_aggregation: T.nilable(ElasticsearchRequest::Aggregation::Nested)
    )
    .returns(ElasticsearchRequest::Aggregation::Filter)
  end
  private_class_method def self.chart_open_before_time_range_aggregation(start_date:, y_axis_aggregation: nil)
    initial_open_aggregation = ElasticsearchRequest::Aggregation::Filter.new(
      slug: :chart_open_before_time_range,
      filter: { bool: {
        must: [
          { range: { "content.created_at": { lt: start_date } } },
          { bool: {
            should: [
              { range: { "content.closed_at": { gte: start_date } } },
              { bool: { must_not: { exists: { field: "content.closed_at" } } } }
            ] } },
        ] }
      }
    )
    initial_open_aggregation.add_subaggregation(y_axis_aggregation) if y_axis_aggregation.present?
    initial_open_aggregation
  end

  # Build the Elasticsearch aggregation fragment for item/issue/pr created date histogram.
  sig do
    params(
      options: Options,
      y_axis_aggregation: T.nilable(ElasticsearchRequest::Aggregation::Nested)
    )
    .returns(ElasticsearchRequest::Aggregation::DateHistogram)
  end
  private_class_method def self.chart_x_axis_created_aggregation(options:, y_axis_aggregation: nil)
    date_histogram_agg = date_histogram_aggregation(slug: :chart_x_axis_created, field: "content.created_at", options:)
    buckets_path = "_count"

    if y_axis_aggregation.present?
      date_histogram_agg.add_subaggregation(y_axis_aggregation)
      operation = options.y_axis.aggregate.operation.serialize
      y_axis_field_id = options.y_axis_aggregate_field&.id
      buckets_path = "chart_y_axis_aggregation>#{y_axis_field_id}>#{operation}"
    end

    cummulative_sum_agg = ElasticsearchRequest::Aggregation::CumulativeSum.new(slug: :cumulative_data, buckets_path:)
    date_histogram_agg.add_subaggregation(cummulative_sum_agg)
  end

  # Build the Elasticsearch aggregation fragment for the issue closed date histogram.
  sig do
    params(
      options: Options,
      y_axis_aggregation: T.nilable(ElasticsearchRequest::Aggregation::Nested)
    )
    .returns(ElasticsearchRequest::Aggregation::Filter)
  end
  private_class_method def self.chart_x_axis_issue_closed_aggregation(options:, y_axis_aggregation: nil)
    filter_agg = ElasticsearchRequest::Aggregation::Filter.new(
      slug: :chart_x_axis_issue_closed,
      filter: { term: { "content.type": "Issue" } }
    )
    date_histogram_agg = date_histogram_aggregation(slug: :issue_closed_dates, field: "content.closed_at", options:)
    term_agg = ElasticsearchRequest::Aggregation::Terms.new(
      slug: :issue_by_state_reason,
      field: "content.state_reason",
      size: 3000
    )

    if y_axis_aggregation.present?
      date_histogram_agg.add_subaggregation(y_axis_aggregation)
      term_agg.add_subaggregation(y_axis_aggregation)
    end

    date_histogram_agg.add_subaggregation(term_agg)
    filter_agg.add_subaggregation(date_histogram_agg)
  end

  # Build the Elasticsearch aggregation fragment for the pull request closed/merged date histogram.
  sig do
    params(
      options: Options,
      y_axis_aggregation: T.nilable(ElasticsearchRequest::Aggregation::Nested)
    )
    .returns(ElasticsearchRequest::Aggregation::Filter)
  end
  private_class_method def self.chart_x_axis_pr_closed_aggregation(options:, y_axis_aggregation: nil)
    filter_agg = ElasticsearchRequest::Aggregation::Filter.new(
      slug: :chart_x_axis_pr_closed,
      filter: { term: { "content.type": "PullRequest" } }
    )
    date_histogram_agg = date_histogram_aggregation(slug: :pr_closed_dates, field: "content.closed_at", options:)
    term_agg = ElasticsearchRequest::Aggregation::Terms.new(
      slug: :pr_by_state,
      field: "content.state",
      size: 3000
    )

    if y_axis_aggregation.present?
      date_histogram_agg.add_subaggregation(y_axis_aggregation)
      term_agg.add_subaggregation(y_axis_aggregation)
    end

    date_histogram_agg.add_subaggregation(term_agg)
    filter_agg.add_subaggregation(date_histogram_agg)
  end

  # Build historical chart x-axis date values from the Elasticsearch aggregation results and options.
  sig { params(aggregation_results: T.untyped, options: Options).returns(T::Array[String]) }
  private_class_method def self.build_historical_chart_date_values(aggregation_results:, options:)
    data_keys = create_historical_data_keys(options:)
    to_i = data_keys.to_i

    initial_results = aggregation_results.dig("chart_open_before_time_range") || {}
    initial_open = Chartable.to_number(initial_results.dig(*data_keys.path), to_i:)
    created_buckets = aggregation_results.dig("chart_x_axis_created", "buckets") || []
    return [] if created_buckets.empty? && initial_open.zero? && initial_results.dig("doc_count").to_i.zero?

    # Build x-axis date string values
    # These will either be daily or weekly intervals (Mondays) if the time range is large
    first_created_date_value = created_buckets&.first&.dig("key_as_string")
    first_created_date = Date.parse(first_created_date_value) if first_created_date_value.present?
    today = Time.now.utc.to_date
    start_date = options.time_range&.start_date || first_created_date || today
    end_date = options.time_range&.end_date || today

    days_interval = options.time_interval == "1w" ? 7 : 1
    date_values = T.let((start_date..end_date).step(days_interval).map { |date| date.strftime("%Y-%m-%d") }, T::Array[String])
  end

  # Return type of the create_historical_data_keys method containing Elasticsearch response keys for extracting chart data.
  class DataKeys < T::Struct
    # The path to the data in the Elasticsearch response.
    const :path, T::Array[String]
    # Whether data should be an integer (for item counts), else a float (numeric aggregation).
    const :to_i, T::Boolean
  end
  # Returns the Elasticsearch response path for extracting historical chart data for counts or a y_axis aggregation.
  sig { params(options: Options).returns(DataKeys) }
  private_class_method def self.create_historical_data_keys(options:)
    path = ["doc_count"]
    to_i = options.y_axis.aggregate.operation == MemexProjectChart::Operation::Count
    y_axis_field_id = options.y_axis_aggregate_field&.id

    if y_axis_field_id.present?
      y_axis_operation = options.y_axis.aggregate.operation.serialize
      path = ["chart_y_axis_aggregation", y_axis_field_id.to_s, y_axis_operation.to_s, "value"]
    end

    DataKeys.new(path:, to_i:)
  end

  # Build historical chart data from the Elasticsearch aggregation results.
  sig do
    params(
      aggregation_results: T.untyped,
      date_values: T::Array[String],
      options: Options,
      total_hits: Integer,
    )
    .returns(ChartData)
  end
  private_class_method def self.build_historical_chart_data(aggregation_results:, date_values:, options:, total_hits:)
    return ChartData.new(x_axis: ChartData::XAxis.new(values: []), data_series: [], total_count: total_hits) if date_values.empty?

    created_buckets = aggregation_results.dig("chart_x_axis_created", "buckets") || []
    created_dates = created_buckets&.map { |b| b.dig("key_as_string") }
    first_created_date = Date.parse(created_dates[0]) if created_dates.any?
    data_keys = create_historical_data_keys(options:)
    to_i = data_keys.to_i
    zero = to_i ? 0 : 0.0

    # Created counts include all types: issues, pull requests, and draft issues.
    # Items are considered "open" after created.  Draft issues are always open.
    created_counts = T.let(created_buckets.map { |b| Chartable.to_number(b.dig("cumulative_data", "value"), to_i:) }, T::Array[ChartData::IntegerOrFloat])

    # Pad the created_counts array to match the desired date_values range, with 0s before and the last cumulative value after.
    first_date_index = date_values.index(first_created_date&.strftime("%Y-%m-%d")) || date_values.length
    created_counts = Array.new(first_date_index, zero) + created_counts if first_date_index > 0
    created_counts.concat(Array.new(date_values.length - created_counts.length, created_counts[-1]))

    # Build arrays for all potential state counts.
    not_planned_counts, duplicate_counts, completed_counts = issue_closed_counts(aggregation_results:, date_values:, data_keys:)
    closed_pr_counts, merged_pr_counts = pr_closed_counts(aggregation_results:, date_values:, data_keys:)

    # Completed counts are the sum of (normal) closed issues plus merged PRs
    if completed_counts.any?
      completed_counts = completed_counts.zip(merged_pr_counts).map { |completed, merged_pr| Chartable.to_number(completed + T.must(merged_pr), to_i:) } if merged_pr_counts.any?
    else
      completed_counts = merged_pr_counts.presence || Array.new(date_values.length, zero)
    end

    # Open counts are the difference between created and all closed states
    initial_open = Chartable.to_number(aggregation_results.dig("chart_open_before_time_range", *data_keys.path), to_i:)
    open_counts = created_counts.zip(completed_counts, not_planned_counts, duplicate_counts, closed_pr_counts).map do |created, completed, not_planned, duplicate, closed_pr|
      Chartable.to_number(initial_open + created - (completed + (not_planned || zero) + (duplicate || zero) + (closed_pr || zero)), to_i:)
    end

    data_series = [
      build_data_series("Open", open_counts),
      build_data_series("Completed", completed_counts),
      build_data_series("Closed pull requests", closed_pr_counts),
      build_data_series("Not planned", not_planned_counts),
      build_data_series("Duplicate", duplicate_counts),
    ].compact

    ChartData.new(
      x_axis: ChartData::XAxis.new(values: date_values),
      data_series:,
      total_count: total_hits,
    )
  end

  # Check for a large 'max' unspecified time range, and adjust the chart data from daily to weekly intervals if needed.
  # Each weekly Monday date will contain the cumulative value of the following Sunday.
  # For example, if the following array of daily dates and open issue counts span several years, then convert to weekly dates.
  #   Default daily date bins: [Wed Aug 5, Thu Aug 6,  Fri Aug 7, ...,  Sat Nov 9], open counts: [1, 3,  3,  ..., 54]
  #   Weekly Monday date bins: [Mon Aug 3, Mon Aug 10, Mon Aug 17, ..., Mon Nov 4], open counts: [3, 10, 14, ..., 54]
  sig { params(chart_data: ChartData, options: Options, total_hits: Integer).returns(ChartData) }
  private_class_method def self.adjust_historical_time_interval(chart_data:, options:, total_hits:)
    return chart_data if options.time_range.present? || chart_data.x_axis.values.empty?

    first_date = Date.parse(chart_data.x_axis.values.first)
    last_date = Date.parse(chart_data.x_axis.values.last)
    interval = Options.calculate_time_interval(start_date: first_date, end_date: last_date)
    return chart_data if interval == "1d"

    # Adjust the x-axis values for weekly bins, starting on Monday and ending on Sunday (keyed on the Monday dates)
    weekly_time_range = Options.create_time_range(start_date: first_date, end_date: last_date, time_interval: "1w")
    weekly_date_values = (weekly_time_range.start_date..weekly_time_range.end_date).step(7).map { |date| date.strftime("%Y-%m-%d") }

    # The index of the first Sunday date in the original daily data. Ex: 6 - (Wed - Mon) = 4, and data[4] is the first Sunday.
    first_sunday_date_index = 6 - (first_date - weekly_time_range.start_date)

    # Reduce the data series to weekly counts, mapping Monday dates to the cumulative counts of the following Sunday.
    weekly_series = chart_data.data_series.map do |data_series|
      data = data_series.data
      weekly_data = (first_sunday_date_index...data.length).step(7).map { |i| T.must(data[i]) }
      weekly_data.append(T.must(data.last)) unless weekly_time_range.end_date == last_date
      ChartData::DataSeries.new(name: data_series.name, data: weekly_data)
    end

    ChartData.new(
      x_axis: ChartData::XAxis.new(values: weekly_date_values),
      data_series: weekly_series,
      total_count: total_hits
    )
  end

  # Process issue closed counts, separating into "not planned", "duplicate", and normal "completed" states.
  sig do
    params(
      aggregation_results: T::Hash[T.untyped, T.untyped],
      date_values: T::Array[String],
      data_keys: DataKeys,
    )
    .returns([T::Array[ChartData::IntegerOrFloat], T::Array[ChartData::IntegerOrFloat], T::Array[ChartData::IntegerOrFloat]])
  end
  private_class_method def self.issue_closed_counts(aggregation_results:, date_values:, data_keys:)
    issue_closed_buckets = aggregation_results.dig("chart_x_axis_issue_closed", "issue_closed_dates", "buckets")
    return [[], [], []] if issue_closed_buckets.blank?

    to_i = data_keys.to_i
    zero = to_i ? 0 : 0.0
    values_length = date_values.length
    completed_counts = Array.new(values_length, zero)
    not_planned_counts = Array.new(values_length, zero)
    duplicate_counts = Array.new(values_length, zero)

    first_date = issue_closed_buckets[0].dig("key_as_string")
    first_date_index = date_values.index(first_date) || 0
    data_index = 0
    cumulative_duplicate_count = zero
    cumulative_not_planned_count = zero
    cumulative_completed_count = zero

    issue_closed_buckets.each_with_index do |bucket, index|
      data_index = first_date_index + index
      duplicate_count = zero
      not_planned_count = zero
      closed_count = Chartable.to_number(bucket.dig(*data_keys.path), to_i:)

      if closed_count > zero
        state_buckets = bucket.dig("issue_by_state_reason", "buckets")
        if state_buckets.present?
          state_buckets.each do |state_bucket|
            state = state_bucket.fetch("key", "")
            data = Chartable.to_number(state_bucket.dig(*data_keys.path), to_i:)
            case state
            when "duplicate"
              duplicate_count = data
            when "not_planned"
              not_planned_count = data
            end
          end
        end
      end

      cumulative_duplicate_count += duplicate_count
      cumulative_not_planned_count += not_planned_count
      cumulative_completed_count += (closed_count - duplicate_count - not_planned_count)

      not_planned_counts[data_index] = cumulative_not_planned_count
      duplicate_counts[data_index] = cumulative_duplicate_count
      completed_counts[data_index] = cumulative_completed_count
    end

    # Repeat the last cumulative value for any remaining days in the arrays.
    not_planned_counts.fill(not_planned_counts[data_index], data_index)
    duplicate_counts.fill(duplicate_counts[data_index], data_index)
    completed_counts.fill(completed_counts[data_index], data_index)

    [not_planned_counts, duplicate_counts, completed_counts]
  end

  # Process PR closed counts, separating into "closed" (not merged) and "completed" (merged) states.
  sig do
    params(
      aggregation_results: T::Hash[T.untyped, T.untyped],
      date_values: T::Array[String],
      data_keys: DataKeys,
    )
    .returns([T::Array[ChartData::IntegerOrFloat], T::Array[ChartData::IntegerOrFloat]])
  end
  private_class_method def self.pr_closed_counts(aggregation_results:, date_values:, data_keys:)
    pr_closed_buckets = aggregation_results.dig("chart_x_axis_pr_closed", "pr_closed_dates", "buckets")
    return [[], []] if pr_closed_buckets.blank?

    to_i = data_keys.to_i
    zero = to_i ? 0 : 0.0
    values_length = date_values.length
    closed_pr_counts = Array.new(values_length, zero)
    merged_pr_counts = Array.new(values_length, zero)

    first_date = pr_closed_buckets[0].dig("key_as_string")
    first_date_index = date_values.index(first_date) || 0
    data_index = 0
    cumulative_closed_pr_count = zero
    cumulative_merged_pr_count = zero

    pr_closed_buckets.each_with_index do |bucket, index|
      data_index = first_date_index + index
      merged_count = zero
      closed_count = Chartable.to_number(bucket.dig(*data_keys.path), to_i:)

      if closed_count > zero
        state_buckets = bucket.dig("pr_by_state", "buckets")
        if state_buckets.present?
          state_buckets.each do |state_bucket|
            state = state_bucket.fetch("key", "")
            merged_count = Chartable.to_number(state_bucket.dig(*data_keys.path), to_i:) if state == "merged"
          end
        end
      end

      cumulative_closed_pr_count += (closed_count - merged_count)
      cumulative_merged_pr_count += merged_count

      closed_pr_counts[data_index] = cumulative_closed_pr_count
      merged_pr_counts[data_index] = cumulative_merged_pr_count
    end

    # Repeat the last cumulative value for any remaining days in the arrays.
    closed_pr_counts.fill(closed_pr_counts[data_index], data_index)
    merged_pr_counts.fill(merged_pr_counts[data_index], data_index)

    [closed_pr_counts, merged_pr_counts]
  end

  sig { params(name: String, data: T.nilable(T::Array[ChartData::IntegerOrFloat])).returns(T.nilable(ChartData::DataSeries)) }
  private_class_method def self.build_data_series(name, data)
    return if data.nil? || data.empty? || data.all?(&:zero?)
    ChartData::DataSeries.new(name:, data:)
  end

  sig do
    params(slug: Symbol, field: String, options: Options)
    .returns(ElasticsearchRequest::Aggregation::DateHistogram)
  end
  private_class_method def self.date_histogram_aggregation(slug:, field:, options:)
    # adjust time range so that both min and max dates are inclusive, adjusting to a weekly interval if needed.
    min = options.time_range&.start_date
    max = options.time_range&.end_date&.next_day
    hard_bounds = (min.present? || max.present?) ? { min:, max: } : nil

    ElasticsearchRequest::Aggregation::DateHistogram.new(
      slug:,
      field:,
      calendar_interval: options.time_interval,
      format: "yyyy-MM-dd",
      hard_bounds:
    )
  end
end
