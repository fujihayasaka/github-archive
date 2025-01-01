# typed: strict
# frozen_string_literal: true

# This abstract module encapsulates behavior to group data on Memex field values supported in GitHub Projects in Elasticsearch.
#
# This is intended to be included in MemexProjectColumn::Field::Base that serves as the base class for all Memex fields.
# This serves as an interface along with default, overridable method implementations, where applicable.
module MemexProjectColumn::Interface::Groupable
  extend T::Helpers
  include MemexProjectColumn::Helper::AggregationMetadata
  abstract!

  class MetadataError < StandardError; end

  # Abbreviation to improve readability of types in this module.
  ElasticsearchRequest = Elastomer::Interfaces::Api::Search::Request

  requires_ancestor { MemexProjectColumn::Field::Base }

  # Elasticsearch uses a null key ({ "bucket" => nil }) to group items with no value
  # for the requested field. We replace this key with the below string when building
  # the response for the client.
  # It's designed to help prevent collisions with user-defined group values.
  MISSING_VALUE_GROUP_KEY = MemexProjectColumn::Interface::Queryable::MISSING_VALUE_KEY

  DEFAULT_GROUPS_PAGE_SIZE = 10
  DEFAULT_GROUPED_ITEMS_PAGE_SIZE = 25

  # _noValue items/groups are last when sorted ascending, and first when sorted descending.
  NO_VALUE_SORT = 1000

  # If there is a lag in ES indexing and a value is stale compared to known values, sort it prior to _noValue.
  STALE_VALUE_SORT = 999

  # The slug for the aggregation required to aggregate on the 'parent' docs of a bucket
  # instead of the nested 'sibling' or 'child' docs.
  REVERSE_NESTED_SLUG = :reverse_nested_data

  # The slug for the optional aggregation required when sub-aggregating
  # a group by its items' field values.
  METRICS_SLUG = :metrics

  # The field identifier used by callers that can be mapped to the field to group by.
  #
  # This is used in the Elasticsearch query and serves as the key for the returned field group results.
  sig(:final) { returns(Integer) }
  def group_by_key
    id
  end

  # Returns the aggregation fragment used to retrieve a page
  # of groups, with optional multi-level secondary grouping, and their items.
  #
  # @param query The unmodified query string as it was originally provided by the end-user.
  # @param sort The order in which to return item results.
  # @param source_fields The subset of fields from the document that stored in Elasticsearch.
  # @params options The set of options specifying the desired grouping parameters for the query.
  # @params filters Optional additional filtering to apply to limit the queried group values.
  sig(:final) do
    params(
      query: String,
      sort: Search::Queries::CursorPagination::Sort,
      source_fields: T.any(T::Array[String], T::Boolean),
      options: Options,
      context: Search::Memex::Context,
    )
    .returns(ElasticsearchRequest::Aggregation::Collection)
  end
  def group_by_fragment(query:, sort:, source_fields:, options:, context:)
    unless index.index_running_version_8_plus?
      # Nested composite aggregations are only compatible with Elasticsearch v8
      raise ArgumentError, "Grouping by #{data_type} is only supported on Elasticsearch v8"
    end

    aggregations = ElasticsearchRequest::Aggregation::Collection.new

    if options.secondary_grouping_options.present?
      # Multi-level grouping is used in the Memex board view.
      # Board columns (primary groups) can only be fields with limited, static groups, i.e., single-select and iteration fields.
      # Board swimlanes (secondary groups) can be of any field type, with an unknown number of groups.
      # To enable pagination for secondary groups of any field type, we invert the ES query
      # such that the top-level aggregation is a Composite aggregration for secondary groups
      # and the nested aggregation is a Terms aggregation for primary groups.

      # Add a top-level primary group aggregation just for group totals and metadata
      aggregations.concat(build_all_group_aggregations(query:, sort: [], source_fields:, options:, context:))

      # Add the primary groups with items as a nested aggregation of the secondary groups
      primary_group_agg = build_all_group_aggregations(query:, sort:, source_fields:, options:, context:, is_nested_primary: true)
      secondary_options = T.must(options.secondary_grouping_options)
      aggregations.concat(secondary_options.field.build_all_group_aggregations(
        query:, sort:, source_fields:, options: secondary_options, context:, primary_group_agg:
      ))
    else
      aggregations.concat(build_all_group_aggregations(query:, sort:, source_fields:, options:, context:))
    end
    aggregations
  end

  # An optional, default group query string to limit the groups returned from Elasticsearch.
  sig { overridable.returns(T.nilable(String)) }
  def default_group_query
    nil
  end

  # Return the subset of static group values that match options.group_filters, if specified.
  sig { overridable.params(query: String, options: Options, context: Search::Memex::Context).returns(T.nilable(T::Array[String])) }
  def filter_static_group_values(query:, options:, context:)
    filters = options.group_filters(query:, context:)
    # If there are any static_group_values, clone the array so any mutations don't affect the original.
    return nil unless values = static_group_values&.clone
    return values unless filters.present?

    # Loop through the filters and iteratively reduce the found set of values.
    filters.each_with_object(values) do |filter, matched_values|
      comparator = MemexProject::Comparator.new(filter.values, negated: filter.negated?)
      # We use select! to reduce the array to just the values matching the current filter value.
      matched_values.select! { comparator.matches?(_1) }
    end
  end

  # Override this hook when all possible groups for this field type is a reasonably short list (e.g. < 500 groups)
  # that can be derived from configuration.
  #
  # For example, single-select fields have a fixed list of at most 100 options. That field overrides this hook
  # such that it returns the title of each configured option as a group value.
  sig { overridable.returns(T.nilable(T::Array[String])) }
  def static_group_values; end

  sig(:final) { returns(T::Boolean) }
  def static_groups? = !static_group_values.nil?

  sig(:final) { returns(T::Boolean) }
  def dynamic_groups? = !static_groups?

  # The path to the field that defines the grouping value in the Elasticsearch document for this field type.
  #
  # This path should start from the top-level `field_values` key of the item document. Below are the relevant parts
  # of the item document:
  #
  #  {
  #    field_values: [
  #      { assignees_value: [{ login: "lerebear" }, { login: "talune" }] },
  #      { single_select_value: { name: "Todo" } }
  #    ]
  #  }
  #
  #  EXAMPLES:
  #
  #    class Assignees < MemexProject::Field
  #      def group_by_value_path
  #        "field_values.assignees_value.login.keyword"
  #      end
  #    end
  #
  #    class SingleSelect < MemexProject::Field
  #      def group_by_value_path
  #        "field_values.single_select_value.name.keyword"
  #      end
  #    end
  #
  sig { overridable.returns(String) }
  def group_by_value_path
    ""
  end

  # Applies any necessary transformations to the key for an aggregation bucket before it is used to populate
  # a the `group_value` attribute of a `Group` object.
  #
  # If you override this method you must handle MISSING_VALUE_GROUP_KEY as a possible value for the
  # `aggregation_bucket_key` parameter.
  #
  # @param aggregation_bucket_key The value returned from Elasticsearch at the
  #   `$.<group_by_key>.values.buckets[*].key.bucket` path of the aggregation response (see the method comment on
  #   `paginated_groups` to understand the shape of the aggregation response).
  sig { overridable.params(aggregation_bucket_key: T.any(String, Numeric)).returns(String) }
  def group_value(aggregation_bucket_key) = aggregation_bucket_key.to_s

  # Whether or not this field implements the groupable functionality.
  #
  # Consumers should override this method when they would like to render richer UI elements to represent a group of
  # items (e.g. a more complex group header in the table view).
  #
  # At present, we assume that any field that overrides this to make it return true also represents its data in
  # Elasticsearch (via the `Queryable#elasticsearch_mapping` interface) as an object that can be passed as the
  # `field_value_document` argument to the `group_by_value` method in this interface. If the field represents its data
  # in Elasticsearch differently, then `group_by_value` will not work, and we will fail to generate group metadata for
  # this field when asked. This is a place where we can extend `Groupable` to be more capable in the future, but we
  # opt not to at the moment for lack of need.
  sig { overridable.returns(T::Boolean) }
  def has_group_metadata? = false

  # The path to the field that defines the grouping metadata object in the Elasticsearch document for this field type.
  #
  # A grouping metadata object can be any object that implements the `Serializable` interface.
  #
  # This path should start from the top-level `field_values` key of the item document. Below are the relevant parts
  # of the item document:
  #
  #   {
  #     field_values: [
  #       { assignees_value: [{ id: 7 }, { id: 8 }] },
  #       { single_select_value: { id: 8 } }
  #     ]
  #   }
  #
  #  EXAMPLES:
  #
  #    class Assignees < MemexProject::Field
  #      def metadata_id_path
  #        "field_values.assignees_value.id"
  #      end
  #    end
  #
  #    class SingleSelect < MemexProject::Field
  #      def metadata_id_path
  #        "field_values.single_select_value.id"
  #      end
  #    end
  #
  sig { overridable.returns(T.nilable(String)) }
  def metadata_id_path
    nil
  end

  # Given a list of metadata object IDs retrieved by `metadata_id_path`, this method should
  # return a Hash that maps each of those IDs to a `Serializable` instance.
  #
  # Any IDs for which there is no relevant `Serializable` instance should be omitted from the
  # returned Hash.
  #
  # EXAMPLE:
  #
  #    class Assignees < MemexProject::Field
  #      def preload_metadata_objects(metadata_object_ids)
  #        User.where(id: metadata_object_ids).index_by(&:id)
  #      end
  #    end
  #
  sig { overridable.params(metadata_object_ids: T::Array[T.untyped]).returns(T::Hash[T.untyped, MemexProjectColumn::IDataSource]) }
  def preload_metadata_objects(metadata_object_ids)
    {}
  end

  # Given the raw Elasticsearch result from a composite aggregation, returns a flat array of groups with associated
  # pagination data.
  #
  # For more information on composite aggregations, see:
  # https://www.elastic.co/guide/en/elasticsearch/reference/current/search-aggregations-bucket-composite-aggregation.html
  #
  # EXAMPLE
  #
  #   `aggregation_results` looks like this:
  #
  #     {
  #       "231": {                             // This top level key is the stringified result of `group_by_key`
  #         "values": {
  #           "groups": {
  #             "after_key": {
  #               "bucket": "Iteration 10"
  #             },
  #             "buckets": [
  #               {
  #                 "key": {
  #                   "bucket": "Iteration 11"  // The value passed to `group_value` that acts as a unique identifier for the group
  #                 },
  #                 "reverse_nested_data": {
  #                   "items": {
  #                     "hits": [...]          // The items in the group
  #                   }
  #                 }
  #               }
  #             ]
  #           }
  #         }
  #       }
  #     }
  #
  #   This method extracts the "buckets" key in that result to provide the value of the `groups` key in the
  #   return value.
  #
  # @param query The unmodified query string as it was originally provided by the end-user.
  # @param aggregation_results The hash returned from an Elasticsearch composite aggregation query.
  # @param cursor The cursor into the list of groups that was provided
  sig(:final) do
    params(
      query: String,
      aggregation_results: T::Hash[T.untyped, T.untyped],
      options: Options,
      context: Search::Memex::Context,
    )
    .returns(PaginatedGroups)
  end
  def paginated_groups(query:, aggregation_results:, options:, context:)
    unpaginated_groups = collect_unpaginated_groups(aggregations: aggregation_results, query:, options:, context:)

    add_group_metadata!(unpaginated_groups) if options.add_group_metadata?
    sort_groups!(unpaginated_groups, query:, options:, context:) if static_groups?

    apply_pagination(unpaginated_groups:, options:)
  end

  # Builds an array of GroupedItems, each identified by primary and secondary ids.
  #
  # These grouped items are at the intersection of the subset of paged primary and seconday groups,
  # and each represent a "cell" of items in a Memex board view with swimlanes.
  # Currently, this are only created when using secondary grouping.
  sig(:final) do
    params(
      aggregation_results: T::Hash[T.untyped, T.untyped],
      options: Options,
      primary_groups: PaginatedGroups,
      secondary_groups: T.nilable(PaginatedGroups)
    )
    .returns(T::Array[GroupedItems])
  end
  def grouped_items(aggregation_results:, options:, primary_groups:, secondary_groups:)
    return collect_grouped_items(parent_aggregation: aggregation_results, groups: primary_groups, options:) unless secondary_groups

    secondary_options = T.must(options.secondary_grouping_options)
    secondary_buckets = all_group_buckets(
      aggregations: aggregation_results,
      groups_key: secondary_options.group_by_key_symbol,
      no_group_value_key: secondary_options.no_group_value_key
    )
    # Iterate over the previously sorted, paged subset of secondary groups
    secondary_groups.nodes.each_with_object([]) do |secondary_group, result|
      secondary_bucket = group_bucket(group_buckets: secondary_buckets, group_value: secondary_group.group_value)
      next if secondary_bucket.nil?

      result.concat(collect_grouped_items(parent_aggregation: secondary_bucket, options:, groups: primary_groups, secondary_group:))
    end
  end

  sig do
    params(
      parent_aggregation: T::Hash[T.untyped, T.untyped],
      options: Options,
      groups: PaginatedGroups,
      secondary_group: T.nilable(Group)
    )
    .returns(T::Array[GroupedItems])
  end
  def collect_grouped_items(parent_aggregation:, options:, groups:, secondary_group: nil)
    group_buckets = all_group_buckets(
      aggregations: parent_aggregation,
      groups_key: options.group_by_key_symbol,
      no_group_value_key: options.no_group_value_key
    )
    groups.nodes.each_with_object([]) do |group, result|
      items = group_bucket(group_buckets:, group_value: group.group_value)&.dig("items")
      # Skip empty groups when collecting secondary grouped items
      next if items&.dig("hits", "hits").blank? && secondary_group.present?

      result << GroupedItems.new(
        group_by_key: group.group_by_key,
        group_value: group.group_value,
        secondary_group_by_key: secondary_group&.group_by_key,
        secondary_group_value: secondary_group&.group_value,
        grouped_items_page_size: options.grouped_items_page_size,
        top_hits_aggregation: items
      )
    end
  end

  # Return an array of all group buckets, including the no_group_value group
  sig do params(aggregations: T::Hash[T.untyped, T.untyped], groups_key: Symbol, no_group_value_key: Symbol)
    .returns(T::Array[T::Hash[T.untyped, T.untyped]])
  end
  private def all_group_buckets(aggregations:, groups_key:, no_group_value_key:)
    buckets = aggregations.dig(groups_key.to_s, "values", "groups", "buckets").dup
    no_value_bucket = aggregations.dig(no_group_value_key.to_s)
    buckets.push({ "key" => MISSING_VALUE_GROUP_KEY, "no_group_value" => no_value_bucket })
  end

  # Return the group bucket matching the provided group_value
  sig do params(group_buckets: T::Array[T::Hash[T.untyped, T.untyped]], group_value: String)
    .returns(T.nilable(T::Hash[T.untyped, T.untyped]))
  end
  private def group_bucket(group_buckets:, group_value:)
    bucket = group_buckets.find do |b|
      key_value = b.dig("key")
      key_value = key_value.dig("bucket") if key_value.is_a?(Hash)
      group_value(key_value) == group_value
    end
    bucket&.dig(group_value == MISSING_VALUE_GROUP_KEY ? "no_group_value" : REVERSE_NESTED_SLUG.to_s)
  end

  # Builds an unpaginated list of all of the groups that might comprise the final page that we return.
  #
  # There are three categories of groups:
  #
  #   1. Non-empty groups that are computed dynamically in Elasticsearch based on field values.
  #   2. Empty groups that are derived from static configuration on a field.
  #   3. The synthetic "no value" group that collects all items that have a nil value for the field we're grouping on.
  #
  # This method combines all three groups into a single list and returns them all.
  sig(:final) do
    params(
      aggregations: T::Hash[T.untyped, T.untyped],
      query: String,
      options: Options,
      context: Search::Memex::Context,
    )
    .returns(T::Array[Group])
  end
  private def collect_unpaginated_groups(aggregations:, query:, options:, context:)
    non_empty_groups = aggregations.dig(options.group_by_key_symbol.to_s, "values", "groups", "buckets").map do |bucket|
      aggregation_bucket_key = bucket.dig("key", "bucket")
      Group.new(
        aggregation_bucket_key:,
        group_value: group_value(aggregation_bucket_key),
        group_by_key:,
        top_hits_aggregation: bucket.dig(REVERSE_NESTED_SLUG.to_s, "items"),
        item_count: bucket.dig("doc_count"),
        field_metrics: collect_field_metrics(
          field_metric_options: options.field_metric_options,
          metric_agg_results: bucket.dig(REVERSE_NESTED_SLUG.to_s, METRICS_SLUG.to_s),
        )
      )
    end

    empty_groups = empty_groups(non_empty_groups:, query:, options:, context:)

    no_value_bucket = aggregations.dig(options.no_group_value_key.to_s)
    no_value_group_count = no_value_bucket.dig("doc_count").to_i
    no_value_group = if no_value_group_count > 0
      Group.new(
        group_by_key:,
        top_hits_aggregation: no_value_bucket.dig("items"),
        item_count: no_value_group_count,
        field_metrics: collect_field_metrics(
          field_metric_options: options.field_metric_options,
          metric_agg_results: no_value_bucket.dig(METRICS_SLUG.to_s),
        )
      )
    end

    all_groups = non_empty_groups + empty_groups

    # If present, the 'no value' group can be ordered either first or last in the array of groups for pagination.
    is_first_page = options.cursor.nil?
    if no_value_group.present? && options.missing_value_group_order == MissingValueGroupOrder::First && is_first_page
      all_groups.prepend(no_value_group)
    elsif no_value_group.present? && options.missing_value_group_order == MissingValueGroupOrder::Last
      all_groups.append(no_value_group)
    end

    all_groups
  end

  sig { params(unpaginated_groups: T::Array[Group], options: Options).returns(PaginatedGroups) }
  private def apply_pagination(unpaginated_groups:, options:)
    cursor = options.cursor

    # If necessary, drop static groups that appear before the cursor in the sorted list of unpaginated groups.
    if static_groups? && cursor.present?
      cursor_index = unpaginated_groups.index { |g| g.group_value == cursor["bucket"] }.to_i
      unpaginated_groups = unpaginated_groups[(cursor_index + 1)..-1].to_a
    end

    # Compute page info and then truncate groups to requested page size.
    has_next_page = unpaginated_groups.length > options.groups_page_size
    has_previous_page = unpaginated_groups.any? && cursor.present?
    paginated_groups = unpaginated_groups.take(options.groups_page_size)

    last_group = paginated_groups.last

    # This block computes a value that we use as a cursor through groups via the `after_key` variable below.
    bucket_key = if dynamic_groups?
      # Use the key generated by Elasticsearch itself as the cursor.
      last_group&.aggregation_bucket_key
    else
      # Static groups are not retrieved from Elasticsearch, so they don't have the aggregation bucket key that we
      # would typically use for a cursor through groups. Instead, we use `group_value` as the cursor.
      last_group&.group_value != MISSING_VALUE_GROUP_KEY ? last_group&.group_value : nil
    end

    # Derive our own `after_key` (a cursor through Elasticsearch aggregation buckets).
    #
    # Elasticsearch documentation warns against deriving your own `after_key` from buckets:
    # https://www.elastic.co/guide/en/elasticsearch/reference/current/search-aggregations-bucket-composite-aggregation.html#_pagination
    #
    # However, based on https://github.com/elastic/elasticsearch/pull/50475, we believe we can safely ignore this
    # warning because we don't apply any pipeline aggregations filters to the `composite` response.
    after_key = { "bucket" => bucket_key }

    PaginatedGroups.new(nodes: paginated_groups, has_next_page:, has_previous_page:, after_key:)
  end

  # An aggregation fragment used to retrieve a simplified sample item when required for group metadata.
  sig(:final) { returns(T.nilable(ElasticsearchRequest::Aggregation::TopHits)) }
  private def group_by_metadata_sample_agg
    return unless metadata_id_path.present?

    ElasticsearchRequest::Aggregation::TopHits.new(
      slug: :items,
      size: 1,
      fields: group_metadata_search_fields,
    )
  end

  sig(:final) { params(groups: T::Array[Group]).void }
  private def add_group_metadata!(groups)
    metadata_object_ids = T.let(Set.new, T::Set[Integer])
    metadata_id_to_group = T.let({}, T::Hash[Integer, Group])

    groups.each do |group|
      metadata_object_id = group_by_metadata_object_id(group)
      next unless metadata_object_id

      metadata_object_ids.add(metadata_object_id)
      metadata_id_to_group[metadata_object_id] = group
    end

    metadata_object_by_id = preload_metadata_objects(metadata_object_ids.to_a)

    metadata_object_ids.each do |id|
      group = metadata_id_to_group[id]
      next unless group

      metadata_object = metadata_object_by_id[id]
      next unless metadata_object

      group.metadata = metadata_object
    end
  end

  # Returns the the set of repository Ids from all groups in the provided response.
  sig do
    params(
      response: Search::Responses::GroupedMemexProjectItemResponse,
      options: Options
    )
    .returns(T::Array[Integer])
  end
  def redactable_group_repo_ids(response:, options:)
    field_repo_ids = []

    if options.is_secondary
      field_repo_ids += repo_ids_from_metadata(nodes: response.secondary_groups&.nodes || [])
    else
      field_repo_ids += repo_ids_from_metadata(nodes: response.primary_groups.nodes)
      secondary_options = options.secondary_grouping_options
      if secondary_options.present?
        field_repo_ids += secondary_options.field.redactable_group_repo_ids(response:, options: secondary_options)
      end
    end
    field_repo_ids.compact.uniq
  end

  # Redacts group data in the provided response for any with unauthorized repository Ids.
  sig do
    params(
      response: Search::Responses::GroupedMemexProjectItemResponse,
      options: Options,
      unauthorized_repo_ids: T::Array[Integer]
    )
    .void
  end
  def redact_group_data(response:, options:, unauthorized_repo_ids:)
    if options.is_secondary
      redact_node_data!(nodes: (response.secondary_groups&.nodes || []), unauthorized_repo_ids:)
    else
      redact_node_data!(nodes: response.primary_groups.nodes, unauthorized_repo_ids:)
      secondary_options = options.secondary_grouping_options
      if secondary_options.present?
        secondary_field = secondary_options.field
        secondary_field.redact_group_data(response:, options: secondary_options, unauthorized_repo_ids:)
      end
    end
  end

  sig(:final) do
    params(
      non_empty_groups: T::Array[Group],
      query: String,
      options: Options,
      context: Search::Memex::Context,
    )
    .returns(T::Array[Group])
  end
  private def empty_groups(non_empty_groups:, query:, options:, context:)
    return [] unless static_groups? && options.include_empty_groups

    non_empty_group_values = non_empty_groups.map(&:group_value).to_set

    T.must(filter_static_group_values(query:, options:, context:)).each_with_object([]) do |group_value, result|
      unless non_empty_group_values.include?(group_value)
        result << Group.new(
          group_value:,
          group_by_key:,
          item_count: 0,
          field_metrics: collect_field_metrics(
            field_metric_options: options.field_metric_options,
            metric_agg_results: nil
          )
        )
      end
    end
  end

  sig(:final) do
    params(
      groups: T::Array[Group],
      query: String,
      options: Options,
      context: Search::Memex::Context,
    )
    .void
  end
  private def sort_groups!(groups, query:, options:, context:)
    group_index_by_group_value = T.must(filter_static_group_values(query:, options:, context:))
      .each_with_index
      .each_with_object({}) { |(value, index), result| result[value] = index }

    groups.sort_by! do |group|
      is_stale_value = false

      sort_index = if (index = group_index_by_group_value[group.group_value])
        index
      elsif group.group_value == MISSING_VALUE_GROUP_KEY
        options.missing_value_group_order == MissingValueGroupOrder::First ? -NO_VALUE_SORT : NO_VALUE_SORT
      else
        is_stale_value = true
      end

      if is_stale_value
        STALE_VALUE_SORT
      elsif options.ignore_group_sort
        sort_index
      elsif options.sort_direction == "desc"
        -sort_index
      else
        sort_index
      end
    end
  end

  # Retrieves the MySQL database ID of the object that is used to represent metadata for the given group (that was
  # retrieved from Elasticsearch).
  sig { overridable.params(group: Group).returns(T.untyped) }
  private def group_by_metadata_object_id(group)
    return unless metadata_id_path
    return unless field_values = group.partial_item_document&.dig("field_values")

    metadata_object_id(
      field_values,
      group.group_value,
      group_by_value_path,
      T.must(metadata_id_path),
    )
  end

  sig(:final) { returns(T::Array[String]) }
  private def group_metadata_search_fields
    if metadata_id_path.present?
      [
        metadata_id_path,
        group_by_value_path,
      ]
    else
      []
    end
  end

  # Returns the page size for groups that we actually submit to Elasticsearch.
  #
  # This can be larger than the page size the user requested, in which case the response will be truncated to the
  # user-requested size later on.
  sig(:final) { params(query: String, options: Options, context: Search::Memex::Context).returns(Integer) }
  private def internal_groups_page_size(query:, options:, context:)
    # For known groups, the items that fall into each group are retrieved from Elasticsearch even though the groups
    # themselves are retrieved from static configuration. That means that we must use a page size large enough to
    # capture all known groups so that we don't accidentally consider a group that was not in the ES response to be
    # empty.
    page_size = if static_groups?
      T.must(filter_static_group_values(query:, options:, context:)).length
    else
      options.groups_page_size
    end

    # Request one more group than necessary (a "lookahead") to determine if there is a next page.
    page_size + 1
  end

  # The order in which to return the groups.
  sig { overridable.params(options: Options).returns(String) }
  private def group_by_order(options:)
    options.sort_direction || "asc"
  end

  # Build the Elasticsearch aggregation fragment for all named and "_noValue" group values
  # along with nested items or secondary grouping with nested items, if applicable.
  # This is for internal usage within Groupable, but must be left public for calling on the secondary field.
  # if is_nested_primary is true, then build a Terms primary_group_agg for nesting within the secondary group agg.
  sig do
    params(
      query: String,
      sort: Search::Queries::CursorPagination::Sort,
      source_fields: T.any(T::Array[String], T::Boolean),
      options: Options,
      context: Search::Memex::Context,
      primary_group_agg: T.nilable(ElasticsearchRequest::Aggregation::Collection),
      is_nested_primary: T::Boolean
    )
    .returns(ElasticsearchRequest::Aggregation::Collection)
  end
  def build_all_group_aggregations(query:, sort:, source_fields:, options:, context:, primary_group_agg: nil, is_nested_primary: false)
    named_group_values_aggregation = build_named_group_values_aggregation(query:, sort:, source_fields:, options:, primary_group_agg:, is_nested_primary:, context:)
    no_group_value_aggregation = build_no_group_value_aggregation(sort:, source_fields:, options:, primary_group_agg:, is_nested_primary:)

    ElasticsearchRequest::Aggregation::Collection.new([
      named_group_values_aggregation,
      no_group_value_aggregation
    ])
  end

  # Build the Elasticsearch aggregation fragment for named group values
  # and nested items or secondary groups.
  sig do
    params(
      query: String,
      sort: Search::Queries::CursorPagination::Sort,
      source_fields: T.any(T::Array[String], T::Boolean),
      options: Options,
      primary_group_agg: T.nilable(ElasticsearchRequest::Aggregation::Collection),
      is_nested_primary: T::Boolean,
      context: Search::Memex::Context,
    )
    .returns(ElasticsearchRequest::Aggregation::Nested)
  end
  private def build_named_group_values_aggregation(query:, sort:, source_fields:, options:, primary_group_agg:, is_nested_primary:, context:)
    named_group_values_aggregation = ElasticsearchRequest::Aggregation::Nested.new(
      slug: options.group_by_key_symbol,
      path: "field_values",
    )

    values_filter_aggregation = ElasticsearchRequest::Aggregation::Filter.new(
      slug: :values,
      filter: elasticsearch_field_value_term_filter,
    )

    # By default, we use Elasticsearch Composite aggregations for grouping since that allows ES pagination.
    # However, Composite aggregations are not allowed within a reverse nested aggregation used with
    # multi-level grouping, so we must resort to the simple Terms aggregation for the nested primary groups.
    groups_aggregation = if options.has_secondary_grouping? && is_nested_primary
      ElasticsearchRequest::Aggregation::Terms.new(
        slug: :groups,
        field: group_by_value_path,
        order: index.index_running_version_8_plus? ? { _key: group_by_order(options:) } : { _term: group_by_order(options:) },
      )
    else
      ElasticsearchRequest::Aggregation::Composite.new(
        slug: :groups,
        size: internal_groups_page_size(query:, options:, context:),
        sources: [
          ElasticsearchRequest::Aggregation::Composite::TermsSource.new(
            slug: :bucket,
            field: group_by_value_path,
            order: ElasticsearchRequest::Aggregation::Composite::Order.deserialize(group_by_order(options:)),
            missing_bucket: false,
          )
        ],
        # To support custom sort order, Field's with static group values are paginated
        # manually in Groupable#apply_pagination instead of with Elasticsearch :after.
        after: static_groups? ? nil : options.cursor,
      )
    end

    is_top_level_primary = options.has_secondary_grouping? && !is_nested_primary

    reverse_nested_aggregration = ElasticsearchRequest::Aggregation::ReverseNested.new(
      slug: REVERSE_NESTED_SLUG,
    )
    metrics_aggregation = metrics_subaggregation(options.field_metric_options)

    # Metrics are supported at the "group" level, not the "cell" level.
    # So only add the sub-aggregation for top-level primary or secondary groups.
    if !is_nested_primary && metrics_aggregation.present?
      reverse_nested_aggregration.add_subaggregation(
        metrics_aggregation
      )
    end

    # If field_metric_options are specified, a reverse_nested agg is required.
    # If no field_metric_options are specified, the reverse_nested agg is only necessary
    # when top_hits items are required.
    if !is_top_level_primary || metrics_aggregation.present?
      groups_aggregation.add_subaggregation(
        reverse_nested_aggregration
      )
    end

    named_group_values_aggregation.add_subaggregation(
      values_filter_aggregation.add_subaggregation(
        groups_aggregation
      )
    )

    # For multi-level grouping, we only need group counts and metrics
    # for the top-level primary aggregation, so we can return early.
    return named_group_values_aggregation if is_top_level_primary

    # For single-level grouping or nested primary grouping, we also need to return project items.
    if options.is_secondary && primary_group_agg.present?
      metadata_sample_item_agg = group_by_metadata_sample_agg if options.include_group_metadata
      reverse_nested_aggregration.add_subaggregation(metadata_sample_item_agg) if metadata_sample_item_agg.present?
      reverse_nested_aggregration.aggs.concat(primary_group_agg)
    else
      reverse_nested_aggregration.add_subaggregation(
        items_top_hits_aggregation(sort:, source_fields:, options:)
      )
    end

    named_group_values_aggregation
  end

  # Build the Elasticsearch aggregation fragment for the "_noValue" group
  # and nested items or secondary groups.
  sig do
    params(
      sort: Search::Queries::CursorPagination::Sort,
      source_fields: T.any(T::Array[String], T::Boolean),
      options: Options,
      primary_group_agg: T.nilable(ElasticsearchRequest::Aggregation::Collection),
      is_nested_primary: T::Boolean
    )
    .returns(ElasticsearchRequest::Aggregation::Filter)
  end
  private def build_no_group_value_aggregation(sort:, source_fields:, options:, primary_group_agg: nil, is_nested_primary: false)
    no_group_value_aggregation = ElasticsearchRequest::Aggregation::Filter.new(
      slug: options.no_group_value_key,
      filter: {
        bool: {
          must_not: existence_fragment
        }
      },
    )

    # Conditionally add metrics sub-aggregation for the no value bucket
    metrics_aggregation = metrics_subaggregation(options.field_metric_options)
    no_group_value_aggregation.add_subaggregation(metrics_aggregation) if metrics_aggregation.present?

    # For multi-level grouping, we only want group counts for the top-level primary aggregation.
    is_top_level_primary = options.has_secondary_grouping? && !is_nested_primary
    return no_group_value_aggregation if is_top_level_primary

    # For single-level grouping or nested primary grouping, we also want to return project items.
    if options.is_secondary && primary_group_agg.present?
      no_group_value_aggregation.aggs.concat(primary_group_agg)
    else
      # :no_group_value isn't a nested aggregation, so we don't need the
      # reverse_nested sub-aggregation here
      no_group_value_aggregation.add_subaggregation(
        items_top_hits_aggregation(sort:, source_fields:, options:)
      )
    end

    no_group_value_aggregation
  end

  # The nested fragment used to retrieve the first set
  # of items within each group.
  sig do
    overridable
    .params(
      sort: Search::Queries::CursorPagination::Sort,
      source_fields: T.any(T::Array[String], T::Boolean),
      options: Options
    )
    .returns(ElasticsearchRequest::Aggregation::TopHits)
  end
  private def items_top_hits_aggregation(sort:, source_fields:, options:)
    source = if source_fields.is_a?(Array)
      ElasticsearchRequest::Aggregation::TopHits::SourceOptions.new(
        includes: source_fields
      )
    else
      source_fields
    end

    ElasticsearchRequest::Aggregation::TopHits.new(
      slug: :items,
      # Gather this many documents for each bucket (we include one extra doc to determine if there is a next page)
      size: options.grouped_items_page_size + 1,
      fields: group_metadata_search_fields,
      # Filter which fields are returned per document
      # https://www.elastic.co/guide/en/elasticsearch/reference/current/search-fields.html#source-filtering
      _source: source,
      # By default, items are sorted by their score in the main query
      # https://www.elastic.co/guide/en/elasticsearch/reference/current/search-aggregations-metrics-top-hits-aggregation.html#_options_6
      sort:,
    )
  end

  # The optional sub-aggregation used to aggregate the items in each group
  # by the specified field values.
  sig(:final) do
    params(field_metric_options: T.nilable(FieldMetricOptions))
    .returns(T.nilable(ElasticsearchRequest::Aggregation::Nested))
  end
  private def metrics_subaggregation(field_metric_options)
    return nil unless field_metric_options.present?
    nested_values = ElasticsearchRequest::Aggregation::Nested.new(
      slug: METRICS_SLUG,
      path: "field_values",
    )
    field_metric_options.sum.map do |field|
      nested_values.add_subaggregation(
        field.sum_by_aggregation
      )
    end
    nested_values
  end

  sig do
    params(
      field_metric_options: T.nilable(FieldMetricOptions),
      metric_agg_results: T.nilable(T::Hash[String, T.untyped]),
    )
    .returns(T::Array[FieldMetric])
  end
  private def collect_field_metrics(field_metric_options:, metric_agg_results:)
    return [] unless field_metric_options.present?
    field_metric_options.sum.map do |field|
      FieldMetric.new(
        field_id: field.id,
        value: field.get_sum_value(metric_agg_results),
      )
    end
  end

  # The Elastomer index used to query for items.
  sig { abstract.returns(Elastomer::Indexes::MemexProjectItems) }
  private def index; end

  # GraphQL has a very specific contract it expects groupable values to be in.
  # This per-field method can take a group by value and transform it into the proper type expected by the
  # corresponding platform object. For example:
  #   An assignee column groupable value will be returned to the GraphQL client as a
  #   ProjectV2GroupAssigneeValue object.
  sig { abstract.params(group_by_value: T.nilable(String)).returns(T.untyped) }
  def graphql_value(group_by_value); end

  # We currently derive titles server-side and pass them to the client-side via GraphQL.
  # It is arguably presentation logic that only belongs client-side but to not break backwards-compatibility
  # we need to maintain this title derivation logic.
  sig { abstract.params(group_by_value: T.nilable(String)).returns(String) }
  def graphql_title(group_by_value); end
end
