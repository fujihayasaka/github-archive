# typed: strict
# frozen_string_literal: true

class MemexProjectColumn::Field::Iteration < MemexProjectColumn::Field::Base
  include GitHub::Memoizer
  include Helper::GenericField

  RangeQuery = Elastomer::Interfaces::Api::Search::Request::RangeQuery

  sig { override.returns(T::Array[String]) }
  def self.register_processors
    [
      "MemexProjectColumn::Interface::Indexable::Processor::IterationSettingsChange",
      "MemexProjectColumn::Interface::Indexable::Processor::IterationValueCreate",
      "MemexProjectColumn::Interface::Indexable::Processor::IterationValueUpdate",
      "MemexProjectColumn::Interface::Indexable::Processor::IterationValueDestroy",
    ]
  end

  sig { override.returns(Elastomer::Interfaces::Mapping::FieldDataType) }
  def self.elasticsearch_mapping
    Elastomer::Interfaces::Mapping::FieldDataTypes::Object.new(properties: {
      id: Elastomer::Interfaces::Mapping::FieldDataTypes::Keyword.new,
      title: Elastomer::Interfaces::Mapping::FieldDataTypes::KeywordMultiField.new(copy_to: Elastomer::Interfaces::Mapping::MemexProjectItem::FULL_TEXT_SEARCH_FIELDS),
      duration: Elastomer::Interfaces::Mapping::FieldDataTypes::Integer.new,
      start_date: Elastomer::Interfaces::Mapping::FieldDataTypes::Date.new,
    })
  end

  sig { override.params(items: T::Array[MemexProjectItem]).void }
  def preload_elasticsearch_document_data(items)
    GitHub::PrefillAssociations.prefill_associations(items, :memex_project_column_values)
  end

  sig do
    override
      .params(item: MemexProjectItem)
      .returns(Elastomer::Interfaces::Document::MemexProjectItem::IterationValue)
  end
  def elasticsearch_document(item)
    iteration_id = item
      .column_values(columns: [self], require_prefilled_associations: false)
      .first
      .deep_symbolize_keys
      .dig(:value, :id)
    return unless iteration_id

    unless iteration = settings_all_iteration(iteration_id)
      raise CanonicalDataMissingError.new("value for iteration id: #{iteration_id} not found")
    end

    iteration = iteration.deep_symbolize_keys.slice(:id, :title, :start_date, :duration)
    Elastomer::Interfaces::Document::Iteration.new(iteration)
  end

  sig { override.returns(String) }
  def group_by_value_path
    "field_values.#{self.class.value_name}.title.keyword"
  end
  [:chart_by_value_path, :slice_by_value_path].each { |method| alias_method method, :group_by_value_path }

  sig { override.returns(T.nilable(T::Array[String])) }
  memoize def static_group_values
    settings_all_iterations.map { _1["title"] }
  end
  alias_method :static_chart_values, :static_group_values

  # An optional, default group query string to limit the groups returned from Elasticsearch.
  # For Iterations, we default to exclude completed iterations before @current-3,
  # but only for the Board view where include_empty_groups == true
  sig { override.params(options: MemexProjectColumn::Interface::Groupable::Options).returns(T.nilable(String)) }
  def default_group_query(options:)
    if options.group_filters.blank? && options.include_empty_groups
      filter = MemexProjectColumn::Interface::Queryable::FieldValueFilter.new(
        field_object_or_id: id,
        field_value: "<@current-3"
      )
      "-#{filter.filter_term}"
    end
  end

  # Return the subset of static group values (iteration titles) that match options.group_filters, if specified.
  sig { override.params(options: MemexProjectColumn::Interface::Groupable::Options).returns(T.nilable(T::Array[String])) }
  def filter_static_group_values(options:)
    filters = options.group_filters
    return static_group_values unless filters.present?

    iterations = filters.each_with_object(settings_all_iterations.clone) do |filter, matched_iterations|
      comparator = MemexProject::IterationComparator.new(filter.values, negated: filter.negated?, field: self)
      # We use select! to reduce the array to just the iterations matching the current filter value.
      matched_iterations.select! { |iteration| comparator.matches?(iteration) }
    end

    iterations.sort_by { _1["start_date"] }.map { _1["title"] }
  end

  sig { override.returns(T::Boolean) }
  def has_group_metadata? = true

  sig do
    override
    .params(
      field_value_document: T.nilable(T::Hash[T.untyped, T.untyped]),
      group_value: String,
    )
    .returns(T.nilable(String))
  end
  def group_by_metadata_object_id(field_value_document, group_value)
    iterations_by_title.dig(group_value, "id")
  end
  alias_method :slice_by_metadata_object_id, :group_by_metadata_object_id

  sig do
    override
    .params(metadata_object_ids: T::Array[String])
    .returns(T::Hash[String, MemexProjectColumn::Settings::Iteration])
  end
  def preload_group_metadata_objects(metadata_object_ids)
    settings_iterations_objects_all.reduce({}) do |memo, iteration|
      memo[iteration.id] = iteration
      memo
    end
  end
  alias_method :preload_slice_metadata_objects, :preload_group_metadata_objects

  sig(:final) { returns(T::Hash[String, T.untyped]) }
  memoize private def iterations_by_title
    settings_all_iterations.reduce({}) do |memo, iteration|
      memo[iteration["title"]] = iteration
      memo
    end
  end

  # Returns true since all potential slice field values are known (i.e., defined field iterations)
  sig { override.returns(T::Boolean) }
  def known_slices?
    true
  end

  # Override unnest_slices so that iteration field value slices can be sorted
  # by ascending start date and optionally include all other iterations defined in the project.
  sig do
    override
    .params(
      aggregation_results: T::Hash[T.untyped, T.untyped],
      total_hits: Integer
    )
    .returns(T::Hash[T.untyped, T.untyped])
  end
  def unnest_slices(aggregation_results:, total_hits:)
    unnested_slices = super(aggregation_results:, total_hits:)
    unsorted_slices = unnested_slices[:slices]
    # settings_all_iterations are configured iterations returned ordered by start date
    known_value_to_order = settings_all_iterations.each_with_index.reduce({}) do |hash, (iteration, index)|
      hash[iteration["title"]] = index
      hash
    end
    known_value_to_order[MISSING_VALUE_GROUP_KEY] = NO_VALUE_SORT

    sorted_slices = unsorted_slices.sort_by do |slice|
      known_value_to_order[slice["slice_value"]] || STALE_VALUE_SORT
    end
    # optionally append remaining zero-count slice values (iteration titles) that were not fetched from Elasticsearch
    if include_empty_slices
      empty_slices = []
      fetched_values = T.let(unsorted_slices.map { |slice| slice["slice_value"] }.to_set, T::Set[T::untyped])
      settings_all_iterations.each do |iteration|
        value = iteration["title"]
        empty_slices << create_slice(value, 0) unless fetched_values.include?(value)
      end
      empty_slices << create_slice(MISSING_VALUE_GROUP_KEY, 0) unless fetched_values.include?(MISSING_VALUE_GROUP_KEY)
      # TODO: https://github.com/github/projects-platform/issues/1955
      # Since this override method adds additional slices after metadata
      # is added, we have to call `add_slice_metadata!` again on the new slices.
      # This is a temporary solution until the above issue is completed.
      add_slice_metadata!(empty_slices) if include_slice_metadata
      sorted_slices.concat(empty_slices)
    end
    unnested_slices[:slices] = sorted_slices
    unnested_slices
  end

  sig do
    override
      .params(
        values: T::Array[String],
        is_negated: T::Boolean,
        context: Search::Memex::Context
      )
      .returns(T::Hash[T.untyped, T.untyped])
  end
  def query_fragment(values:, is_negated:, context:)
    should_clauses = values.map do |value|
      query_strategy = range_query(value)&.to_hash || term_query(value)
      {
        nested: {
          path: "field_values",
          query: {
            bool: {
              must: [
                {
                  term: {
                    "field_values.field_id": { value: id },
                  }
                },
                query_strategy
              ]
            }
          }
        }
      }
    end

    wrap_query_fragment(should_clauses:, is_negated:)
  end

  sig { override.returns(T::Hash[T.untyped, T.untyped]) }
  def existence_fragment
    {
      nested: {
        path: "field_values",
        query: {
          bool: {
            filter: [
              {
                term: {
                  "field_values.field_id": id,
                }
              },
              exists: {
                field: "field_values.#{self.class.value_name}"
              },
            ]
          }
        }
      }
    }
  end

  sig do
    override
      .params(context: Elastomer::Interfaces::Document::MemexProjectItem::SeedContext)
      .returns(Elastomer::Interfaces::Document::MemexProjectItem::IterationValue)
  end
  def seed_elasticsearch_document(context)
    iteration_id = settings_iteration_ids.sample(context.num_single_select_values).first
    return unless iteration_id
    iteration = T.must(settings_all_iteration(iteration_id)).deep_symbolize_keys.slice(:id, :title, :start_date, :duration)
    Elastomer::Interfaces::Document::Iteration.new(iteration)
  end

  sig do
    override
      .params(direction: String)
      .returns(T::Hash[T.untyped, T.untyped])
  end
  def sort_fragment(direction:)
    build_version_compatible_sort_fragment(
      direction: direction,
      sort_by: "field_values.#{self.class.value_name}.start_date",
    )
  end

  sig { params(value: String).returns(T.nilable(RangeQuery)) }
  def range_query(value)
    iteration_filter_values = MemexProject::IterationRangeComparator.new([value])
    patterns = iteration_filter_values.range_patterns
    return nil if patterns.empty?

    # macro range
    match = patterns.values.map { |val| val.match(MemexProject::FilterValueResolver::ITERATION_MACRO_REGEX) }.compact
    range_clause = if match.present?
      start_dates = MemexProject::FilterValueResolver.new(self, iteration_key: "start_date").resolve(patterns.values)
      patterns.keys.zip(start_dates).to_h
    else
      # iteration name range
      iteration_filter_values.range_clause(self.settings["configuration"]["iterations"], patterns)
    end

    return nil if range_clause.nil?

    RangeQuery.new(
      field_path: "field_values.#{self.class.value_name}.start_date",
      operators: RangeQuery::Operators.from_hash(range_clause)
    )
  end

  sig { params(value: String).returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
  def term_query(value)
    return unless iteration_id = MemexProject::FilterValueResolver.new(self).resolve([value]).first

    {
      term: {
        "field_values.#{self.class.value_name}.id": iteration_id
      }
    }
  end

  # GraphQL expected the option's ID, not the option's text for the ProjectV2GroupIterationValue object.
  sig { override.params(group_by_value: T.nilable(String)).returns(T.nilable(String)) }
  def graphql_value(group_by_value)
    # Calling super helps cleanse potential _noValue values
    value = super(group_by_value)

    return if value.blank?

    # We store the iteration name in ES so we need to map it back to the column option entry and
    # exchange it for the underlying iteration id for GraphQL.
    iteration = settings_all_iterations.find { |i| i["title"] == group_by_value }

    iteration&.dig("id")
  end

  sig { override.returns(T::Boolean) }
  def self.writeable? = true

  # Returns a value that can be used to sort a MemexProjectItem by a given field.
  #
  # When querying for project items outside of ElasticSearch, this method returns the sortable value
  # for a field to regenerate the same sort order as ElasticSearch. The output for these methods should match
  # what ElasticSearch returns for the sorting order. Depending on the data type and direction, fields could
  # return the max or minimum 64-bit signed integer, a String, or a representation for Infinity.
  #
  # direction   - The direction to sort by, either :asc or :desc.
  # column_data - The data for the column to be sorted, this is JSON data stored in the column record, after
  #               extracting more specific information using the column data type to query through
  #               the MemexProjectItem::ColumnDependency::COLUMN_VALUE_KEYS Hash.
  #
  sig { override.params(direction: Symbol, column_data: T.untyped).returns(T.untyped) }
  def graphql_sortable_column_value(direction:, column_data:)
    if (iteration = self.settings_all_iterations.find { _1["id"] == column_data })
      (iteration["start_date"].to_time(:utc).to_f * 1000).to_i
    else
      direction == :asc ? MAX_64_BIT_SIGNED_INTEGER : MIN_64_BIT_SIGNED_INTEGER
    end
  end
end
