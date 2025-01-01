# typed: strict
# frozen_string_literal: true

class MemexProjectColumn::Field < MemexProjectColumn
  extend T::Sig
  extend T::Helpers
  include Indexable
  include Queryable
  include Sortable
  include Groupable
  include Sliceable
  abstract!

  # Abbreviation to improve readability of types in this module.
  ElasticsearchRequest = Elastomer::Interfaces::Api::Search::Request

  # Hook to exclude fields that we want to prevent from being indexed, at least temporarily. This is useful for removing
  # support for fields without having to remove all related architecture.
  #
  # Note that at the time of writing this only prevents future data from being indexed. The mappings will stay in place until they
  # are specifically removed, and any data already in the index will remain in place until documents containing that data are resynced.
  sig { overridable.returns(T::Boolean) }
  def self.exclude_from_index?
    false
  end

  sig { override.returns(Symbol) }
  def self.data_type
    T.must(self.name).demodulize.underscore.to_sym
  end

  sig { returns(Symbol) }
  def self.value_name
    "#{data_type}_value".to_sym
  end

  sig { override.overridable.returns(T::Array[String]) }
  def self.register_processors
    []
  end

  sig { override.returns(Symbol) }
  def query_slug
    name_slug.to_sym
  end

  sig do
    params(item: MemexProjectItem)
    .returns(T.nilable(Elastomer::Interfaces::Document::MemexProjectItem::FieldValue))
  end
  def elasticsearch_field_value(item)
    value = elasticsearch_document(item)
    # Note that value.present? should return false on any empty values (e.g. nil, "", " ", [], {})
    return nil unless value.present?

    Elastomer::Interfaces::Document::MemexProjectItem::FieldValue.new(
      field_slug: self.name_slug,
      field_type: self.data_type,
      field_id: T.must(id),
      value_name: self.class.value_name,
      value:,
    )
  end

  sig do
    params(item: MemexProjectItem)
    .returns(Elastomer::Interfaces::Api::Request::Script)
  end
  def elasticsearch_field_value_update_script(item)
    if updated_field_value = elasticsearch_field_value(item)
      Elastomer::Interfaces::Api::Request::Script.new(
        # To ensure we don't update unnecessarily, we abort/noop if we find that the value exists already. Otherwise,
        # we proceed by removing the existing metadata and value and replace it with the new one. Note that we don't
        # need to worry about replacing newer data with older data because we're fetching the latest canonical data
        # from the database.
        source: """
          def existing_field_value = ctx._source.field_values.find(field -> field.field_id == params.field_id);
          if (existing_field_value == params.updated_field_value) {
            ctx.op = 'noop';
          } else {
            ctx._source.field_values.removeIf(field -> field.field_id == params.field_id);
            ctx._source.field_values.add(params.updated_field_value);
          }
        """,
        params: {
          field_id: id,
          updated_field_value: updated_field_value.to_hash
        }
      )
    else
      # If the updated field value is nil, we remove the related field entirely from the field_values array. Note that
      # this will be a noop if the field does not already exist in the array.
      Elastomer::Interfaces::Api::Request::Script.new(
        source: """
          boolean field_removed = ctx._source.field_values.removeIf(field -> field.field_id == params.field_id);
          if (!field_removed) {
            ctx.op = 'noop';
          }
        """,
        params: { field_id: id }
      )
    end
  end

  sig { params(item: MemexProjectItem).returns(Elastomer::Interfaces::Api::Request::Script) }
  def elasticsearch_field_value_and_priority_move_script(item)
    if updated_field_value = elasticsearch_field_value(item)
      metadata = item.elasticsearch_metadata.to_hash
      params = {
        field_id: id,
        updated_field_value: updated_field_value.to_hash,
        priority: item.elasticsearch_metadata.to_hash
      }.merge(metadata)

      Elastomer::Interfaces::Api::Request::Script.new(
        # To ensure we don't update unnecessarily, we abort/noop if we find that the value exists already. Otherwise,
        # we proceed by removing the existing metadata and value and replace it with the new one. Note that we don't
        # need to worry about replacing newer data with older data because we're fetching the latest canonical data
        # from the database.
        source: """
          def existing_field_value = ctx._source.field_values.find(field -> field.field_id == params.field_id);
          if (existing_field_value == params.updated_field_value) {
            ctx.op = 'noop';
          } else {
            ctx._source.field_values.removeIf(field -> field.field_id == params.field_id);
            ctx._source.field_values.add(params.updated_field_value);
            #{ metadata.map { |k, _| "ctx._source.#{k} = params.#{k};" }.join("\n") }
          }
        """,
        params:
      )
    else
      # If the updated field value is nil, we remove the related field entirely from the field_values array. Note that
      # this will be a noop if the field does not already exist in the array.
      Elastomer::Interfaces::Api::Request::Script.new(
        source: """
          boolean field_removed = ctx._source.field_values.removeIf(field -> field.field_id == params.field_id);
          if (!field_removed) {
            ctx.op = 'noop';
          }
        """,
        params: { field_id: id }
      )
    end
  end

  sig do
    override
      .params(values: T::Array[String], is_negated: T::Boolean, context: Search::Memex::Context)
      .returns(T::Hash[T.untyped, T.untyped])
  end
  def query_fragment(values:, is_negated:, context:)
    {}
  end

  sig do
    override
      .params(direction: String)
      .returns(T::Hash[T.untyped, T.untyped])
  end
  def sort_fragment(direction:)
    {}
  end

  sig { override.returns(T::Hash[T.untyped, T.untyped]) }
  def existence_fragment
    {}
  end

  # Provides the optional Elasticsearch query fragment to aggregate on slice_by field values.
  # This returns total counts for each distinct field value.  Missing/nil values are not included.
  # The count of missing/nil slice values is calculated by subtracting the sum of value counts
  # from the total hits of all documents matching the overall query filter.
  sig { override.params(key_prefix: String).returns(ElasticsearchRequest::Aggregation::Collection) }
  def slice_by_fragment(key_prefix: "")
    slice_by_aggregation = ElasticsearchRequest::Aggregation::Nested.new(
      slug: "#{key_prefix}slice_by".to_sym,
      path: "field_values",
    )
    values_filter_aggregation = ElasticsearchRequest::Aggregation::Filter.new(
      slug: :values,
      filter: {
        term: {
          "field_values.field_id": { value: id }
        }
      },
    )
    slices_terms_aggregation = ElasticsearchRequest::Aggregation::Terms.new(
      slug: :slices,
      field: slice_by_value_path,
      order: index.index_running_version_8_plus? ? { _key: "asc" } : { _term: "asc" },
      size: MAX_SLICE_VALUES_SIZE,
    )
    if include_slice_metadata && slice_by_metadata_sample_aggregation = slice_by_metadata_sample_agg
      slices_terms_aggregation.add_subaggregation(slice_by_metadata_sample_aggregation)
    end

    slice_by_aggregation.add_subaggregation(
      values_filter_aggregation.add_subaggregation(
        slices_terms_aggregation
      )
    )

    # Gets the counts of items with a nil or missing slice value
    no_slice_value_aggregation = ElasticsearchRequest::Aggregation::Filter.new(
      slug: "#{key_prefix}no_slice_value".to_sym,
      filter: {
        bool: {
          must_not: existence_fragment
        }
      }
    )

    ElasticsearchRequest::Aggregation::Collection.new([
      slice_by_aggregation,
      no_slice_value_aggregation,
    ])
  end

  sig { override.params(group_by_value: T.nilable(String)).returns(T.untyped) }
  def graphql_value(group_by_value)
    return nil if group_by_value.blank? || group_by_value == MISSING_VALUE_GROUP_KEY

    group_by_value
  end

  sig { override.params(group_by_value: T.nilable(String)).returns(String) }
  def graphql_title(group_by_value)
    return "No #{name}" if group_by_value.blank? || group_by_value == MISSING_VALUE_GROUP_KEY

    group_by_value
  end

  sig { override.returns(Elastomer::Indexes::MemexProjectItems) }
  private def index
    @index ||= T.let(Elastomer::Indexes::MemexProjectItems.new, T.nilable(Elastomer::Indexes::MemexProjectItems))
  end

  sig do
    params(direction: String, sort_by: String)
      .returns(T::Hash[T.untyped, T.untyped])
  end
  private def build_version_compatible_sort_fragment(direction:, sort_by:)
    if index.index_running_version_8_plus?
      {
        "#{sort_by}": {
          order: direction,
          nested: {
            path: "field_values",
            filter: {
              bool: {
                must: [
                  {
                    term: {
                      "field_values.field_id": { value: id }
                    }
                  }
                ]
              }
            }
          }
        }
      }
    else
      {
        "#{sort_by}": {
          order: direction,
          nested_path: "field_values",
          nested_filter: {
            bool: {
              must: [
                {
                  term: {
                    "field_values.field_id": { value: id }
                  }
                }
              ]
            }
          }
        }
      }
    end
  end

  # Provides a consistent 'bool' wrapper around the field's optionally negated query_fragment
  sig do params(should_clauses: T::Array[T.nilable(T::Hash[T.untyped, T.untyped])], is_negated: T::Boolean)
    .returns(T::Hash[T.untyped, T.untyped])
  end
  private def wrap_query_fragment(should_clauses:, is_negated:)
    inner_bool_clause = if is_negated
      { must_not: should_clauses.compact }
    else
      # 'minimum_should_match' defaults to 1 in this context anyway,
      # but just being explicit that only 1 'should' term is required to match.
      { should: should_clauses.compact, minimum_should_match: 1 }
    end
    {
      bool: inner_bool_clause
    }
  end
end
