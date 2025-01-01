# typed: strict
# frozen_string_literal: true

# This module defines the interface required to support "slicing" in Projects: the ability to quickly filter a view by
# clicking a on field value in the left-hand side panel.
#
# Rather than including this module directly, most consumers will inherit this interface via
# `MemexProjectColumn::Field::Base`, which is the base class for all fields supported by GitHub Projects.
module MemexProjectColumn::Interface::Sliceable
  extend T::Helpers
  include MemexProjectColumn::Helper::DocumentPath
  include MemexProjectColumn::Helper::AggregationMetadata
  abstract!

  requires_ancestor { MemexProjectColumn::Field::Base }

  # Abbreviation to improve readability of types in this module.
  ElasticsearchRequest = Elastomer::Interfaces::Api::Search::Request

  MISSING_VALUE_GROUP_KEY = MemexProjectColumn::Interface::Groupable::MISSING_VALUE_GROUP_KEY

  # The maximum number of aggregated slice values to return. We will not page slice values.
  # The Elasticsearch default "search.max_buckets" is 65,536.
  # https://www.elastic.co/guide/en/elasticsearch/reference/8.12/search-aggregations-bucket-terms-aggregation.html#search-aggregations-bucket-terms-aggregation-size
  MAX_SLICE_VALUES_SIZE = 500


  # Returns the optional Elasticsearch query fragment to aggregate on slice_by field values.
  # The optional key_prefix can be used to namespace the aggregation keys.
  sig { abstract.params(key_prefix: String).returns(ElasticsearchRequest::Aggregation::Collection) }
  def slice_by_fragment(key_prefix: ""); end

  # Sets whether or not to include slice metadata in the response.
  sig { params(value: T::Boolean).void }
  def include_slice_metadata=(value)
    @include_slice_metadata = T.let(value, T.nilable(T::Boolean))
  end

  # Gets whether or not to include slice metadata in the response.
  # Including metadata may require an additional database query.
  sig { overridable.returns(T::Boolean) }
  def include_slice_metadata
    @include_slice_metadata || false
  end

  # Gets whether or not to include empty slices in the response.
  # Empty slices are additional slice field values in the project, outside the view query filter, with a zero count.
  sig { overridable.returns(T::Boolean) }
  def include_empty_slices
    @include_empty_slices || false
  end

  # Sets whether or not to include empty slices in the response.
  # Empty slices are additional slice field values in the project, outside the view query filter, with a zero count.
  sig { params(value: T.nilable(T::Boolean)).void }
  def include_empty_slices=(value)
    @include_empty_slices = T.let(value, T.nilable(T::Boolean))
  end

  # Returns true if all potential slice field values are known (example: single select options)
  # Otherwise, slice field values are fetched from items in Elasticsearch
  sig { overridable.returns(T::Boolean) }
  def known_slices?
    false
  end

  # The path to the field that defines the slicing value in the Elasticsearch document for this field type.
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
  #      def slice_by_value_path
  #        "field_values.assignees_value.login.keyword"
  #      end
  #    end
  #
  #    class SingleSelect < MemexProject::Field
  #      def slice_by_value_path
  #        "field_values.single_select_value.name.keyword"
  #      end
  #    end
  #
  sig { overridable.returns(String) }
  def slice_by_value_path
    ""
  end

  # Applies any necessary transformations to the key for an aggregation bucket before it is used to populate
  # a the "slice_value" key in the objects returned by `unnest_slices`.
  #
  # If you override this method you must handle MISSING_VALUE_GROUP_KEY as a possible value for the
  # `aggregation_bucket_key` parameter.
  #
  # @param aggregation_bucket_key The value returned from Elasticsearch at the
  #   `$.slice_by.values.slices.buckets[*].key` path of the aggregation response passed to `unnest_slices`.
  sig { overridable.params(aggregation_bucket_key: T.any(String, Numeric)).returns(String) }
  def slice_value(aggregation_bucket_key) = aggregation_bucket_key.to_s

  # The path to the field that defines the slicing metadata object in the Elasticsearch document for this field type.
  #
  # A slicing metadata object is any object that implements the `Sliceable::Metadata` interface.
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
  #      def slice_by_metadata_id_path
  #        "field_values.assignees_value.id"
  #      end
  #    end
  #
  #    class SingleSelect < MemexProject::Field
  #      def slice_by_metadata_id_path
  #        "field_values.single_select_value.id"
  #      end
  #    end
  #
  sig { overridable.returns(T.nilable(String)) }
  def slice_by_metadata_id_path
    nil
  end

  sig { overridable.params(slice: T::Hash[T.untyped, T.untyped]).returns(T.untyped) }
  def slice_by_metadata_object_id(slice)
    return unless slice_by_metadata_id_path
    return unless field_values = slice.dig("metadata_sample", "items", "hits", "hits", 0, "fields", "field_values")

    metadata_object_id(
      field_values,
      slice["slice_value"],
      slice_by_value_path,
      T.must(slice_by_metadata_id_path),
    )
  end

  # Given a list of metadata object IDs retrieved by `slice_by_metadata_id_path`, this method should
  # return a Hash that maps each of those IDs to a `Sliceable::Metadata` instance.
  #
  # Any IDs for which there is no relevant `Sliceable::Metadata` instance should be omitted from the
  # returned Hash.
  #
  # EXAMPLE:
  #
  #    class Assignees < MemexProject::Field
  #      def preload_slice_metadata_objects(metadata_object_ids)
  #        User.where(id: metadata_object_ids).index_by(&:id)
  #      end
  #    end
  #
  sig { overridable.params(metadata_object_ids: T::Array[T.untyped]).returns(T::Hash[T.untyped, Metadata]) }
  def preload_slice_metadata_objects(metadata_object_ids)
    {}
  end

  # Processes the raw Elasticsearch aggregations result to build and return slice value counts.
  # Empty slices are appended with zero total_counts, if include_empty_slices.
  # This method may be overriden when custom sorting is required, such as for single-select fields.
  sig do
    overridable
    .params(
      aggregation_results: T::Hash[T.untyped, T.untyped],
      total_hits: Integer
    )
    .returns(T::Hash[T.untyped, T.untyped])
  end
  def unnest_slices(aggregation_results:, total_hits:)
    # Process the non-zero slices found within the Elasticsearch view filter query
    view_slice_buckets = aggregation_results.dig("slice_by", "values", "slices", "buckets")
    no_slice_value_agg = aggregation_results.dig("no_slice_value")
    no_slice_value_count = no_slice_value_agg&.dig("doc_count") || 0
    if no_slice_value_count > 0
      no_value_bucket = { "key" => nil, "doc_count" => no_slice_value_count }
      view_slice_buckets << no_value_bucket
    end
    slices = view_slice_buckets.map do |slice_bucket|
      build_slice(slice_bucket)
    end

    # Optionally append other slice values found in the project, outside the Elasticsearch view filter query
    if include_empty_slices && !known_slices?
      view_slice_values = T.let(slices.map { |slice| slice["slice_value"] }.to_set, T::Set[T::untyped])
      project_slice_buckets = aggregation_results.dig("project_slice_by", "values", "slices", "buckets") || []
      project_slice_buckets.each do |slice_bucket|
        slice_value = slice_value(slice_bucket["key"]&.to_s)
        slices << build_slice(slice_bucket, 0) unless view_slice_values.include?(slice_value)
      end
      slices << create_slice(MISSING_VALUE_GROUP_KEY, 0) unless view_slice_values.include?(MISSING_VALUE_GROUP_KEY)
    end
    add_slice_metadata!(slices)
    { slices: }
  end

  # Returns a hash representing a slice value with
  # total document count from an Elasticsearch aggregation bucket.
  #
  # The total_count can be overridden when building slices that do
  # not match the current view filter.
  sig do
    params(
      slice_bucket: T.nilable(T::Hash[String, T.untyped]),
      total_count: T.nilable(Integer),
    )
    .returns(T::Hash[T.untyped, T.untyped])
  end
  def build_slice(slice_bucket, total_count = nil)
    slice_result = slice_bucket || {}
    slice_value = slice_value(slice_result["key"]&.to_s || MISSING_VALUE_GROUP_KEY)
    total_count ||= slice_result["doc_count"] || 0
    slice_result.merge(create_slice(slice_value, total_count))
  end

  sig do
    params(slice_value: String, total_count: Integer)
    .returns(T::Hash[T.untyped, T.untyped])
  end
  def create_slice(slice_value, total_count)
    {
      "slice_id" => [id, slice_value],
      "slice_value" => slice_value,
      "total_count" => total_count,
      "is_approximate" => false,
    }
  end

  # Returns the the set of repository Ids from all slices in the provided response.
  sig do
    params(
      response: T.any(Search::Responses::MemexProjectItemResponse, Search::Responses::GroupedMemexProjectItemResponse)
    )
    .returns(T::Array[Integer])
  end
  def redactable_slice_repo_ids(response:)
    field_repo_ids = repo_ids_from_metadata(nodes: response.slices || [])
    field_repo_ids.compact.uniq
  end

  # Redacts slice data in the provided response for any with unauthorized repository Ids.
  sig do
    params(
      response: T.any(Search::Responses::MemexProjectItemResponse, Search::Responses::GroupedMemexProjectItemResponse),
      unauthorized_repo_ids: T::Array[Integer]
    )
    .void
  end
  def redact_slice_data(response:, unauthorized_repo_ids:)
    redact_node_data!(nodes: (response.slices || []), unauthorized_repo_ids:)
  end

  # Returns a hash in the shape of an Elasticsearch aggregation bucket for missing/nil slice value count.
  sig do
    params(buckets: T::Array[T.untyped], total_count: Integer)
    .returns(T::Hash[T.untyped, T.untyped])
  end
  private def build_no_value_slice_bucket(buckets, total_count)
    value_count = buckets.reduce(0) { |sum, b| sum + (b["doc_count"] || 0) }
    no_value_bucket = { "key" => nil, "doc_count" => total_count - value_count }
    no_value_slice = no_value_bucket.merge!(build_slice(no_value_bucket))
    buckets << no_value_slice
    no_value_slice
  end

  # An aggregation fragment used to retrieve a simplified sample item within a slice.
  sig(:final) { returns(T.nilable(ElasticsearchRequest::Aggregation::ReverseNested)) }
  private def slice_by_metadata_sample_agg
    return unless slice_by_metadata_id_path.present?

    aggregation = ElasticsearchRequest::Aggregation::ReverseNested.new(
      slug: :metadata_sample,
    )
    aggregation.add_subaggregation(
      ElasticsearchRequest::Aggregation::TopHits.new(
        slug: :items,
        size: 1,
        fields: slice_metadata_search_fields
      )
    )
  end

  sig(:final) { params(slices: T::Array[T::Hash[String, T.untyped]]).void }
  private def add_slice_metadata!(slices)
    metadata_object_ids = T.let(Set.new, T::Set[Integer])
    metadata_id_to_slice = T.let({}, T::Hash[Integer, T::Hash[T.untyped, T.untyped]])

    slices.each do |slice|
      metadata_object_id = slice_by_metadata_object_id(slice)
      next unless metadata_object_id

      metadata_object_ids.add(metadata_object_id)
      metadata_id_to_slice[metadata_object_id] = slice
    end

    metadata_object_by_id = preload_slice_metadata_objects(metadata_object_ids.to_a)

    metadata_object_ids.each do |id|
      slice = metadata_id_to_slice[id]
      next unless slice

      metadata_object = metadata_object_by_id[id]
      next unless metadata_object

      slice.merge!({ "metadata" => metadata_object })
    end
  end

  sig(:final) { returns(T::Array[String]) }
  private def slice_metadata_search_fields
    if slice_by_metadata_id_path.present?
      [
        slice_by_metadata_id_path,
        slice_by_value_path,
      ]
    else
      []
    end
  end
end
