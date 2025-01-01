# typed: strict
# frozen_string_literal: true

# This module defines the interface required to support insights charting in Projects: the ability to
# represent field data as a chart in the Insights view.
#
# Rather than including this module directly, most consumers will inherit this interface via
# `MemexProjectColumn::Field::Base`, which is the base class for all fields supported by GitHub Projects.
module MemexProjectColumn::Interface::Chartable
  extend T::Helpers
  include MemexProjectColumn::Helper::DocumentPath
  abstract!

  requires_ancestor { MemexProjectColumn::Field::Base }
  ElasticsearchRequest = Elastomer::Interfaces::Api::Search::Request

  # The maximum number of aggregated chart values to return.
  # Historical charts will require the most since there is one value per day over potentially years. Example: 5 x 365 = 1,825.
  # The Elasticsearch default "search.max_buckets" is 65,536.
  # https://www.elastic.co/guide/en/elasticsearch/reference/8.12/search-aggregations-bucket-terms-aggregation.html#search-aggregations-bucket-terms-aggregation-size
  MAX_CHART_VALUES_SIZE = 2_000

  # If there is a lag in ES indexing and a value is stale compared to known values, sort it prior to _noValue.
  STALE_VALUE_SORT = 999

  # This is the "_noValue" constant used to identify an x-axis value or group that not have a value in a particular field.
  MISSING_VALUE_KEY = MemexProjectColumn::Interface::Queryable::MISSING_VALUE_KEY

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
  sig { params(options: MemexProjectColumn::Interface::Chartable::Options).returns(ElasticsearchRequest::Aggregation::Collection) }
  def chart_fragment(options:)
    x_groups_aggregations = options.x_group_field&.build_all_values_aggregations("x_groups")
    chart_aggregations = build_all_values_aggregations("x_axis", x_groups_aggregations)
    chart_aggregations.concat(x_groups_aggregations) if x_groups_aggregations.present?
    chart_aggregations
  end

  # Returns the chart data from the Elasticsearch aggregation results.
  sig(:final) do
    params(
      aggregation_results: T::Hash[T.untyped, T.untyped],
      options: Options
    )
    .returns(ChartData)
  end
  def chart_data(aggregation_results:, options:)
    x_axis_buckets = aggregation_results.dig("chart_x_axis", "x_axis_field", "x_axis_values", "buckets") || []
    x_axis_no_value_bucket = aggregation_results.dig("no_x_axis_value")
    x_axis_chart_data = get_sorted_chart_data(x_axis_buckets, x_axis_no_value_bucket)

    # Return the simple chart data if there is no additional x_axis grouping
    return x_axis_chart_data unless options.x_group_field.present?

    # Otherwise, build a response with multiple data series for x_axis groups
    x_groups_buckets = aggregation_results.dig("chart_x_groups", "x_groups_field", "x_groups_values", "buckets") || []
    x_groups_no_value_bucket = aggregation_results.dig("no_x_groups_value")
    x_groups_chart_data = get_sorted_chart_data(x_groups_buckets, x_groups_no_value_bucket)

    # Create a sorted array of data series for each group, initialized with 0s for each x_axis value
    data_series = x_groups_chart_data.x_axis.values.map do |value|
      ChartData::DataSeries.new(name: value, data: Array.new(x_axis_chart_data.x_axis.values.length, 0))
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
        count = group_bucket.dig("doc_count")&.to_i || 0
        data_by_group_name[value].data[index] = count
      end

      no_group_value_count = x_axis_bucket.dig("no_x_groups_value", "doc_count")&.to_i || 0
      data_by_group_name[MISSING_VALUE_KEY].data[index] = no_group_value_count if no_group_value_count > 0
    end

    ChartData.new(x_axis: x_axis_chart_data.x_axis, data_series:)
  end

  # Build the Elasticsearch aggregation fragment for all named and "_noValue" chart values
  # This is for internal usage within Chartable, but must be left public for calling on the x_axis group field.
  sig do
    params(
      x_type: String,
      nested_groups_aggregations: T.nilable(ElasticsearchRequest::Aggregation::Collection),
    )
    .returns(ElasticsearchRequest::Aggregation::Collection)
  end
  def build_all_values_aggregations(x_type, nested_groups_aggregations = nil)
    named_values_aggregation = build_named_values_aggregation(x_type, nested_groups_aggregations)
    no_value_aggregation = build_no_value_aggregation(x_type, nested_groups_aggregations)

    ElasticsearchRequest::Aggregation::Collection.new([
      named_values_aggregation,
      no_value_aggregation
    ])
  end

  # Build the Elasticsearch aggregation fragment for named x_axis/group values
  sig do
    params(
      x_type: String,
      nested_groups_aggregations: T.nilable(ElasticsearchRequest::Aggregation::Collection),
    )
    .returns(ElasticsearchRequest::Aggregation::Nested)
  end
  private def build_named_values_aggregation(x_type, nested_groups_aggregations)
    named_values_aggregation = ElasticsearchRequest::Aggregation::Nested.new(
      slug: "chart_#{x_type}".to_sym,
      path: "field_values",
    )
    values_filter_aggregation = ElasticsearchRequest::Aggregation::Filter.new(
      slug: "#{x_type}_field".to_sym,
      filter: {
        term: {
          "field_values.field_id": { value: id }
        }
      },
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

    if nested_groups_aggregations.present?
      reverse_nested_aggregration = ElasticsearchRequest::Aggregation::ReverseNested.new(
        slug: :reverse_nested_items,
      )
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
    )
    .returns(ElasticsearchRequest::Aggregation::Filter)
  end
  private def build_no_value_aggregation(x_type, nested_groups_aggregations)
    no_value_aggregation = ElasticsearchRequest::Aggregation::Filter.new(
      slug: "no_#{x_type}_value".to_sym,
      filter: {
        bool: {
          must_not: existence_fragment
        }
      }
    )
    no_value_aggregation.aggs.concat(nested_groups_aggregations) if nested_groups_aggregations.present?
    no_value_aggregation
  end

  # Builds a sorted ChartData object from the provided Elasticsearch response buckets.
  # This may be used to extract and sort simple x_axis values or x_axis group values.
  sig { params(named_buckets: T.untyped, no_value_bucket: T.untyped).returns(MemexProjectColumn::Interface::Chartable::ChartData) }
  private def get_sorted_chart_data(named_buckets, no_value_bucket)
    x_axis = ChartData::XAxis.new(values: [])
    data = T.let([], T::Array[Integer])

    if static_chart_values?
      value_to_data_hash = {}
      named_buckets.each do |bucket|
        value = bucket.dig("key")&.to_s
        x_axis.values << value
        value_to_data_hash[value] = bucket.dig("doc_count")&.to_i
      end
      sort_chart_values!(x_axis.values)
      data = x_axis.values.map { |value| value_to_data_hash[value] }
    else
      named_buckets.each do |bucket|
        x_axis.values << bucket.dig("key")&.to_s
        data << bucket.dig("doc_count")&.to_i
      end
    end

    no_value_count = no_value_bucket&.dig("doc_count")&.to_i || 0

    if no_value_count > 0
      x_axis.values << MISSING_VALUE_KEY
      data << no_value_count
    end

    data_series = T.let([ChartData::DataSeries.new(name: "", data: data)], T::Array[ChartData::DataSeries])
    ChartData.new(x_axis:, data_series:)
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
