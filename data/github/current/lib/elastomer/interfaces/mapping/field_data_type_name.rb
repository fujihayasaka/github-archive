# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Mapping
      # Static options for the names of schema ("mapping") types that you can use to model data that is written to
      # a field in Elasticsearch.
      #
      # Each value that appears in this enum should have a corresponding class in the `Mapping::FieldDataTypes` module
      # that controls how the complete configuration object for the type is serialized for Elasticsearch.
      #
      # These options only cover the types that we already use; we expect to add to this list as we use new types.
      #
      # For a list of all possible types, see:
      # https://www.elastic.co/guide/en/elasticsearch/reference/current/mapping-types.html
      class FieldDataTypeName < T::Enum
        enums do
          Keyword = new
          Wildcard = new
          Text = new
          Date = new
          Integer = new
          Long = new
          Float = new
          Object = new
          Nested = new
          Boolean = new
        end
      end
    end
  end
end
