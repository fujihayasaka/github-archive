# typed: strict
# frozen_string_literal: true

# This module defines the interface required to support insights charting in Projects: the ability to
# represent field data as a chart in the Insights view.
#
# Rather than including this module directly, most consumers will inherit this interface via
# `MemexProjectColumn::Field::Base`, which is the base class for all fields supported by GitHub Projects.
module MemexProjectColumn::Interface::Chartable
  extend T::Helpers
  abstract!

  requires_ancestor { MemexProjectColumn::Field::Base }
  ElasticsearchRequest = Elastomer::Interfaces::Api::Search::Request
  Chartable = MemexProjectColumn::Interface::Chartable

  # The maximum number of aggregated chart values to return.
  # Historical charts will require the most since there is one value per day over potentially years. Example: 5 x 365 = 1,825.
  # The Elasticsearch default "search.max_buckets" is 65,536.
  # https://www.elastic.co/guide/en/elasticsearch/reference/8.12/search-aggregations-bucket-terms-aggregation.html#search-aggregations-bucket-terms-aggregation-size
  MAX_CHART_VALUES_SIZE = 2_000

  # If there is a lag in ES indexing and a value is stale compared to known values, sort it prior to _noValue.
  STALE_VALUE_SORT = 999

  # This is the "_noValue" constant used to identify an x-axis value or group that not have a value in a particular field.
  MISSING_VALUE_KEY = MemexProjectColumn::Interface::Queryable::MISSING_VALUE_KEY

  # The number of decimal places to round chart data values to when using floats rather than integers.
  # This helps prevent values such as 5.006 from being reported as 5.00600004196167
  FLOAT_VALUE_PRECISION = 2

  # Override this hook when all possible chart values for this field type is a reasonably short list (e.g. < 500 values)
  # that can be derived from configuration.
  #
  # For example, single-select fields have a fixed list of at most 100 options. That field overrides this hook
  # such that it returns the title of each configured option as a chart value.
  sig { overridable.returns(T.nilable(T::Array[String])) }
  def static_chart_values; end

  sig(:final) { returns(T::Boolean) }
  def static_chart_values? = !static_chart_values.nil?

  # A field's value path in Elasticsearch is the same for groupable, sliceable, and chartable usage.
  sig { overridable.returns(String) }
  def chart_by_value_path
    ""
  end

  # Returns the Elasticsearch aggregation fragment for fetching chart data.
  # This class method is the primary entry point for building aggregations to fetch historical or current state chart data.
  sig { params(options: Options).returns(ElasticsearchRequest::Aggregation::Collection) }
  def self.chart_fragment(options:)
    if options.historical_chart?
      HistoricalChart.historical_chart_fragment(options:)
    else
      T.must(options.x_axis_field).current_state_chart_fragment(options:)
    end
  end

  # Returns the chart data from the Elasticsearch aggregation results.
  # This class method is the primary entry point for extracting historical or current state chart data.
  sig { params(options: Options, aggregation_results: T::Hash[T.untyped, T.untyped], total_hits: Integer).returns(ChartData) }
  def self.chart_data(options:, aggregation_results:, total_hits:)
    if options.historical_chart?
      HistoricalChart.historical_chart_data(aggregation_results:, total_hits:, options:)
    else
      T.must(options.x_axis_field).current_state_chart_data(aggregation_results:, total_hits:, options:)
    end
  end

  # Returns an integer for the value if `to_i` is true.  Else, returns a rounded float.
  sig { params(value: T.nilable(ChartData::IntegerOrFloat), to_i: T::Boolean).returns(ChartData::IntegerOrFloat) }
  def self.to_number(value, to_i:)
    to_i ? value.to_i : value.to_f.round(FLOAT_VALUE_PRECISION)
  end

  # Returns the Elasticsearch aggregation fragment for fetching current state chart data.
  # This is for internal usage within Chartable.  Consumers whould typically call the chart_fragment class method.
  sig { params(options: Options).returns(ElasticsearchRequest::Aggregation::Collection) }
  def current_state_chart_fragment(options:)
    y_axis_aggregation = options.y_axis_aggregate_field&.build_y_axis_aggregation(options.y_axis.aggregate.operation)
    nested_groups_aggregations = options.x_group_field&.build_all_values_aggregations(x_type: "x_groups", y_axis_aggregation:)

    # Don't include the y_axis_aggregation if already computed in the nested_groups_aggregations
    y_axis_aggregation = nil if nested_groups_aggregations.present?
    chart_aggregations = build_all_values_aggregations(x_type: "x_axis", nested_groups_aggregations:, y_axis_aggregation:)

    # Include a top level aggregation for the groups to get the full set of sorted group values
    chart_aggregations.concat(nested_groups_aggregations) if nested_groups_aggregations.present?
    chart_aggregations
  end

  # Returns the current state chart data from the Elasticsearch aggregation results.
  # This is for internal usage within Chartable.  Consumers whould typically call the chart_data class method.
  sig(:final) do
    params(
      aggregation_results: T::Hash[T.untyped, T.untyped],
      # The number of matching Elasticsearch documents matched in the query.
      total_hits: Integer,
      options: Options
    )
    .returns(ChartData)
  end
  def current_state_chart_data(aggregation_results:, total_hits:, options:)
    x_axis_buckets = aggregation_results.dig("chart_x_axis", "x_axis_field", "x_axis_values", "buckets") || []
    x_axis_no_value_bucket = aggregation_results.dig("no_x_axis_value")
    x_group_field = options.x_group_field
    data_keys = create_data_keys(options:, is_x_axis: true)
    x_axis_chart_data = get_sorted_chart_data(x_axis_buckets, x_axis_no_value_bucket, data_keys:, total_hits:)

    # Return the simple chart data if there is no additional x_axis grouping
    return x_axis_chart_data unless x_group_field

    # Otherwise, build a response with multiple data series for x_axis groups
    x_groups_buckets = aggregation_results.dig("chart_x_groups", "x_groups_field", "x_groups_values", "buckets") || []
    x_groups_no_value_bucket = aggregation_results.dig("no_x_groups_value")
    data_keys = create_data_keys(options:, is_x_axis: false)
    x_groups_chart_data = x_group_field.get_sorted_chart_data(x_groups_buckets, x_groups_no_value_bucket, data_keys:, total_hits:)

    # Create a sorted array of data series for each group, initialized with 0s for each x_axis value.
    #   A 0 value for empty/missing is correct for 90+% of charts where the y-axis is item counts.
    #   However, a 0 value is incorrect/misleading for charts with a y-axis aggregation (e.g. min, max, sum, avg).
    #   Ideally, we would return a null value for the group in this case to distinguish between an actual 0 value and a missing value.
    #   The following issue has been created to consider this change:
    #   https://github.com/github/projects-platform/issues/2752
    to_i = data_keys.to_i
    zero = to_i ? 0 : 0.0
    data_series = x_groups_chart_data.x_axis.values.map do |value|
      ChartData::DataSeries.new(name: value, data: Array.new(x_axis_chart_data.x_axis.values.length, zero))
    end

    # Create hashes for faster lookups of groups and previously sorted x_axis values
    index_by_x_value = x_axis_chart_data.x_axis.values.each_with_index.reduce({}) do |acc, (value, index)|
      acc[value] = index
      acc
    end
    data_by_group_name = data_series.reduce({}) do |acc, data_series|
      acc[data_series.name] = data_series
      acc
    end

    # Loop through all x_axis buckets (named and no_value), loop through all groups within, and update each group data series count
    (x_axis_buckets + [x_axis_no_value_bucket]).each do |x_axis_bucket|
      value = x_axis_bucket.dig("key")&.to_s || MISSING_VALUE_KEY
      index = index_by_x_value[value] || -1
      x_axis_bucket = x_axis_bucket.dig("reverse_nested_items").presence || x_axis_bucket
      group_buckets = x_axis_bucket.dig("chart_x_groups", "x_groups_field", "x_groups_values", "buckets") || []

      group_buckets.each do |group_bucket|
        value = group_bucket.dig("key")&.to_s
        data = Chartable.to_number(group_bucket.dig(*data_keys.with_values), to_i:)
        data_by_group_name[value].data[index] = data
      end

      no_group_value_bucket = x_axis_bucket.dig("no_x_groups_value")
      no_group_value_data = Chartable.to_number(no_group_value_bucket&.dig(*data_keys.with_no_value), to_i:)
      data_by_group_name[MISSING_VALUE_KEY].data[index] = no_group_value_data if no_group_value_data > 0
    end

    ChartData.new(
      x_axis: x_axis_chart_data.x_axis,
      data_series:,
      total_count: total_hits,
    )
  end

  # Returns the nested aggregation fragment for the given y_axis aggregate operation (sum, min, max, avg).
  # This is for internal usage within Chartable, but must be left public for calling on the y_axis aggregation field.
  sig { params(operation: MemexProjectChart::Operation).returns(ElasticsearchRequest::Aggregation::Nested) }
  def build_y_axis_aggregation(operation)
    chart_y_axis_aggregation = ElasticsearchRequest::Aggregation::Nested.new(
      slug: :chart_y_axis_aggregation,
      path: "field_values",
    )
    values_filter_aggregation = ElasticsearchRequest::Aggregation::Filter.new(
      slug: id.to_s.to_sym,
      filter: elasticsearch_field_value_term_filter,
    )

    field = chart_by_value_path
    slug = operation.serialize.to_sym

    y_axis_aggregation = case operation
    when MemexProjectChart::Operation::Sum
      ElasticsearchRequest::Aggregation::Sum.new(slug:, field:)
    when MemexProjectChart::Operation::Min
      ElasticsearchRequest::Aggregation::Min.new(slug:, field:)
    when MemexProjectChart::Operation::Max
      ElasticsearchRequest::Aggregation::Max.new(slug:, field:)
    when MemexProjectChart::Operation::Avg
      ElasticsearchRequest::Aggregation::Avg.new(slug:, field:)
    else
      raise ArgumentError, "The y axis aggregate operation #{operation.serialize} has not been implemented"
    end

    values_filter_aggregation.add_subaggregation(y_axis_aggregation)
    chart_y_axis_aggregation.add_subaggregation(values_filter_aggregation)
    chart_y_axis_aggregation
  end

  # Build the Elasticsearch aggregation fragment for all named and "_noValue" chart values
  # This is for internal usage within Chartable, but must be left public for calling on the x_axis group field.
  sig do
    params(
      x_type: String,
      nested_groups_aggregations: T.nilable(ElasticsearchRequest::Aggregation::Collection),
      y_axis_aggregation: T.nilable(ElasticsearchRequest::Aggregation::Nested)
    )
    .returns(ElasticsearchRequest::Aggregation::Collection)
  end
  def build_all_values_aggregations(x_type:, nested_groups_aggregations: nil, y_axis_aggregation: nil)
    named_values_aggregation = build_named_values_aggregation(x_type, nested_groups_aggregations, y_axis_aggregation)
    no_value_aggregation = build_no_value_aggregation(x_type, nested_groups_aggregations, y_axis_aggregation)

    ElasticsearchRequest::Aggregation::Collection.new([
      named_values_aggregation,
      no_value_aggregation
    ])
  end

  # Return type of the create_data_keys method containing Elasticsearch response keys for extracting chart data.
  class DataKeys < T::Struct
    # The path to the data in named field value aggregations in the Elasticsearch response.
    const :with_values, T::Array[String]
    # The path to the data in the 'no value' aggregations in the Elasticsearch response.
    const :with_no_value, T::Array[String]
    # Whether data should be an integer (for item counts), else a float (numeric aggregation).
    const :to_i, T::Boolean
  end

  # Returns the Elasticsearch response path for extracting chart data for counts or a y_axis aggregation.
  sig { params(options: Options, is_x_axis: T::Boolean).returns(DataKeys) }
  private def create_data_keys(options:, is_x_axis:)
    with_values = ["doc_count"]
    with_no_value = ["doc_count"]
    to_i = options.y_axis.aggregate.operation == MemexProjectChart::Operation::Count

    has_groups = options.x_group_field.present?
    y_axis_field_id = options.y_axis_aggregate_field&.id
    has_y_axis_aggregation_data = y_axis_field_id.present? && !(is_x_axis && has_groups)

    if has_y_axis_aggregation_data
      y_axis_operation = options.y_axis.aggregate.operation.serialize
      with_no_value = ["chart_y_axis_aggregation", y_axis_field_id.to_s, y_axis_operation.to_s, "value"]
      with_values = ["reverse_nested_items"] + with_no_value
    end

    DataKeys.new(with_values:, with_no_value:, to_i:)
  end

  # Build the Elasticsearch aggregation fragment for named x_axis/group values
  sig do
    params(
      x_type: String,
      nested_groups_aggregations: T.nilable(ElasticsearchRequest::Aggregation::Collection),
      y_axis_aggregation: T.nilable(ElasticsearchRequest::Aggregation::Nested)
    )
    .returns(ElasticsearchRequest::Aggregation::Nested)
  end
  private def build_named_values_aggregation(x_type, nested_groups_aggregations, y_axis_aggregation)
    named_values_aggregation = ElasticsearchRequest::Aggregation::Nested.new(
      slug: "chart_#{x_type}".to_sym,
      path: "field_values",
    )
    values_filter_aggregation = ElasticsearchRequest::Aggregation::Filter.new(
      slug: "#{x_type}_field".to_sym,
      filter: elasticsearch_field_value_term_filter,
    )
    x_axis_terms_aggregation = ElasticsearchRequest::Aggregation::Terms.new(
      slug: "#{x_type}_values".to_sym,
      field: chart_by_value_path,
      order: index.index_running_version_8_plus? ? { _key: "asc" } : { _term: "asc" },
      size: MAX_CHART_VALUES_SIZE,
    )

    named_values_aggregation.add_subaggregation(
      values_filter_aggregation.add_subaggregation(
        x_axis_terms_aggregation
      )
    )

    if y_axis_aggregation.present?
      reverse_nested_aggregration = ElasticsearchRequest::Aggregation::ReverseNested.new(slug: :reverse_nested_items)
      reverse_nested_aggregration.add_subaggregation(y_axis_aggregation)
      x_axis_terms_aggregation.add_subaggregation(reverse_nested_aggregration)
    end

    if nested_groups_aggregations.present?
      reverse_nested_aggregration = ElasticsearchRequest::Aggregation::ReverseNested.new(slug: :reverse_nested_items)
      reverse_nested_aggregration.aggs.concat(nested_groups_aggregations)
      x_axis_terms_aggregation.add_subaggregation(reverse_nested_aggregration)
    end

    named_values_aggregation
  end

  # Build the Elasticsearch aggregation fragment for the "_noValue" x_axis/group
  sig do
    params(
      x_type: String,
      nested_groups_aggregations: T.nilable(ElasticsearchRequest::Aggregation::Collection),
      y_axis_aggregation: T.nilable(ElasticsearchRequest::Aggregation::Nested)
    )
    .returns(ElasticsearchRequest::Aggregation::Filter)
  end
  private def build_no_value_aggregation(x_type, nested_groups_aggregations, y_axis_aggregation)
    no_value_aggregation = ElasticsearchRequest::Aggregation::Filter.new(
      slug: "no_#{x_type}_value".to_sym,
      filter: { bool: { must_not: existence_fragment } }
    )
    no_value_aggregation.add_subaggregation(y_axis_aggregation) if y_axis_aggregation.present?
    no_value_aggregation.aggs.concat(nested_groups_aggregations) if nested_groups_aggregations.present?
    no_value_aggregation
  end

  # Builds a sorted ChartData object from the provided Elasticsearch response buckets.
  # This may be used to extract and sort simple x_axis values or x_axis group values.
  # This is for internal usage within Chartable, but must be left public for calling on the x_axis group field.
  sig { params(named_buckets: T.untyped, no_value_bucket: T.untyped, data_keys: DataKeys, total_hits: Integer).returns(ChartData) }
  def get_sorted_chart_data(named_buckets, no_value_bucket, data_keys:, total_hits:)
    x_axis = ChartData::XAxis.new(values: [])
    data_series = T.let([], T::Array[ChartData::DataSeries])
    data = T.let([], T::Array[ChartData::IntegerOrFloat])
    to_i = data_keys.to_i

    if static_chart_values?
      value_to_data_hash = T.let({}, T::Hash[String, ChartData::IntegerOrFloat])
      named_buckets.each do |bucket|
        value = bucket.dig("key")&.to_s
        x_axis.values << value
        value_to_data_hash[value] = Chartable.to_number(bucket.dig(*data_keys.with_values), to_i:)
      end
      sort_chart_values!(x_axis.values)
      data = x_axis.values.map { |value| T.must(value_to_data_hash[value]) }
    else
      named_buckets.each do |bucket|
        x_axis.values << bucket.dig("key")&.to_s
        data << Chartable.to_number(bucket.dig(*data_keys.with_values), to_i:)
      end
    end

    # Exclude _noValue data if it's nil or represents 0 matching item documents (i.e., not a y-axis aggregation value of 0).
    no_value_data = Chartable.to_number(no_value_bucket&.dig(*data_keys.with_no_value), to_i:)
    exclude_no_value_data = no_value_data.zero? && no_value_bucket&.dig("doc_count").to_i.zero?

    unless exclude_no_value_data
      x_axis.values << MISSING_VALUE_KEY
      data << no_value_data
    end

    if data.any?
      data_series << ChartData::DataSeries.new(name: "", data:)
    end

    ChartData.new(
      x_axis:,
      data_series:,
      total_count: total_hits,
    )
  end

  # Sorts the provided values in place if the field has known static_values.
  sig(:final) do
    params(
      values: T::Array[String],
    )
    .void
  end
  private def sort_chart_values!(values)
    static_values = static_chart_values
    return unless static_values

    index_by_value = static_values
      .each_with_index
      .each_with_object({}) { |(value, index), result| result[value] = index }

    values.sort_by! { |value| index_by_value[value] || STALE_VALUE_SORT }
  end
end
