# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Helper::AggregationMetadata
  extend T::Helpers

  # Retrieves the MySQL database ID of the object that is used to represent metadata for a particular field value.
  #
  # EXAMPLE
  #
  #   metadata_object_id(
  #     [
  #       {
  #         "assignees_value.login.lowercased_keyword" => [
  #           "lerebear",
  #           "jayspadie"
  #         ]
  #         "assignees_value.id" => [
  #           123,
  #           456
  #         ]
  #       }
  #     ],
  #     "lerebear",
  #     "field_values.assignee_value.login.lowercased_keyword",
  #     "field_values.assignee_value.id"
  #   )
  #
  #   => 123
  #
  # @param field_values Data retrieved from the `field_values` field in the Elasticsearch document for a project item.
  #   This must be in the format returned by the `fields` option of an Elasticsearch query:
  #   https://www.elastic.co/guide/en/elasticsearch/reference/8.13/search-fields.html
  # @param target_value The value of the aggregation bucket for which we want to retrieve metadata.
  # @param value_path The path used to extract the aggregation bucket value from a field value document.
  # @param metadata_id_path The path used to extract the metadata object ID from the field value document.
  sig do
    params(
      field_values: T::Array[T::Hash[String, T.untyped]],
      target_value: T.untyped,
      value_path: String,
      metadata_id_path: String,
    )
    .returns(T.nilable(Integer))
  end
  private def metadata_object_id(field_values, target_value, value_path, metadata_id_path)
    value_subpath = value_path.gsub(/\Afield_values\./, "")
    metadata_id_subpath = metadata_id_path.gsub(/\Afield_values\./, "")

    # Find a `field_value` document for the aggregation field in particular (amongst the values for all fields).
    field_value_document = field_values.find { _1.dig(value_subpath) }
    return unless field_value_document

    value = field_value_document.dig(value_subpath)

    # Some values are arrays (e.g. a list of `assignees`), and others are plain hashes (e.g. `repository`).
    # Normalize everything as an array so that we can call `find` on the result.
    value_index = Array.wrap(value).find_index(target_value)
    return unless value_index

    Array.wrap(field_value_document.dig(metadata_id_subpath))[value_index]
  end
end
