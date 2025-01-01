# typed: strict
# frozen_string_literal: true

# Instances of this class should be created via the `build` factory method. That method will execute the query it is
# given against Elasticsearch, and then return an instance of this class, which wraps the Elasticsearch response with
# pagination information that is styled after GraphQL: https://graphql.org/learn/pagination/. That instance of this
# class can then be serialized to JSON with the `to_hash` method.
#
# This is considered the parent class of `GroupedMemexItemsApiResponse` and `FlatMemexItemsApiResponse`
#
# EXAMPLE:
#
#   response = Search::Responses::MemexItemsApiResponse.build(query:, serializer:)
#   render(json: response.to_hash)
module Search
  module Responses
    class MemexItemsApiResponse < T::Struct
      extend T::Sig

      # Internal class that represents the total number of items in the underlying collection of items
      # independent of page size. This value may be approximate if the collection too large to count efficiently.
      class TotalCount < T::Struct
        extend T::Sig

        const :value, Integer
        const :is_approximate, T::Boolean

        sig { returns(T::Hash[T.untyped, T.untyped]) }
        def to_hash
          {
            value: value,
            isApproximate: is_approximate
          }
        end
      end

      # Internal class that represents a slice value when slicing is enabled.
      class Slice < T::Struct
        extend T::Sig

        const :slice_id, String
        const :slice_value, String
        const :slice_metadata, T.nilable(T::Hash[T.untyped, T.untyped])
        const :total_count, TotalCount

        sig { returns(T::Hash[T.untyped, T.untyped]) }
        def to_hash
          {
            sliceId: slice_id,
            sliceValue: slice_value,
            sliceMetadata: slice_metadata,
            totalCount: total_count.to_hash,
          }.compact
        end
      end

      SerializerProc = T.type_alias do
        T.proc.params(models: T::Array[MemexProjectItem]).returns(T::Array[T::Hash[T.untyped, T.untyped]])
      end

      # Factory method that returns an instance of this class constructed with the result of an Elasticsearch query.
      #
      # @param query The query to execute against Elasticsearch
      # @param serializer A lambda function that produces the actual JSON objects representing project items that
      #   are returned to the client
      #
      # @raises Search::Queries::CursorPagination::ParameterError when pagination params in `query` are invalid
      sig do
        params(query: Search::Queries::MemexProjectItemQuery, serializer: SerializerProc)
        .returns(T.any(FlatMemexItemsApiResponse, GroupedMemexItemsApiResponse))
      end
      def self.build(query:, serializer:)
        response = query.execute
        build_from_response(response: response, serializer: serializer)
      end

      # Factory method that returns an instance of this class constructed from an Elasticsearch MemexProjectItemResponse.
      sig do
        params(
          response: T.any(Search::Responses::MemexProjectItemResponse, Search::Responses::GroupedMemexProjectItemResponse),
          serializer: SerializerProc
        )
        .returns(T.any(FlatMemexItemsApiResponse, GroupedMemexItemsApiResponse))
      end
      def self.build_from_response(response:, serializer:)
        if response.is_a?(Search::Responses::GroupedMemexProjectItemResponse)
          GroupedMemexItemsApiResponse.build(response, serializer)
        else
          FlatMemexItemsApiResponse.build(response, serializer)
        end
      end

      # Returns an array of Slice items for initializing slices in a new instance of this class
      sig do
        params(response: T.any(Search::Responses::MemexProjectItemResponse, Search::Responses::GroupedMemexProjectItemResponse))
        .returns(T.nilable(T::Array[MemexItemsApiResponse::Slice]))
      end
      def self.build_slices(response)
        return nil unless response.sliced?
        (response.slices || []).map do |s|
          Slice.new(
            slice_id: s.dig("slice_id"),
            slice_value: s.dig("slice_value"),
            slice_metadata: s.dig("slice_metadata"),
            total_count: TotalCount.new(value: s.dig("total_count"), is_approximate: s.dig("is_approximate")),
          )
        end
      end
    end
  end
end
