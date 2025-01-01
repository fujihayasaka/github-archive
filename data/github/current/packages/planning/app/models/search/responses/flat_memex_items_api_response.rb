# typed: strict
# frozen_string_literal: true

# This class represents a JSON response that we can return from our internal API endpoints to the Projects web
# client.
#
# Instances of this class should be created via the `build` factory method. That method will execute the query it is
# given against Elasticsearch, and then return an instance of this class, which wraps the Elasticsearch response with
# pagination information that is styled after GraphQL: https://graphql.org/learn/pagination/. That instance of this
# class can then be serialized to JSON with the `to_hash` method.
#
# EXAMPLE:
#
#   response = MemexItemsApiResponse.build(query:, serializer:)
#   render(json: response.to_hash)
module Search
  module Responses
    class FlatMemexItemsApiResponse < T::Struct
      extend T::Sig

      # A serialized page of items (nil if returning grouped items)
      const :nodes, T.nilable(T::Array[T::Hash[T.untyped, T.untyped]])

      # An non-serialized array of slice values (nil if slicing does not apply)
      const :slices, T.nilable(T::Array[MemexItemsApiResponse::Slice])

      # Information about this page of items (or groups of items)
      const :page_info, Search::Responses::PageInfo, default: Search::Responses::PageInfo.new

      # Information about the total number of items in a given project independent of page size.
      const :total_count, T.nilable(MemexItemsApiResponse::TotalCount)

      SerializerProc = T.type_alias do
        T.proc.params(models: T::Array[MemexProjectItem]).returns(T::Array[T::Hash[T.untyped, T.untyped]])
      end

      # Returns a Hash representation of this response that can be passed as the `json` key to
      # the `render` method of a Rails controller.
      sig { returns(T::Hash[T.untyped, T.untyped]) }
      def to_hash
        {
          nodes: nodes,
          pageInfo: page_info.to_hash,
          slices: slices,
          totalCount: total_count&.to_hash,
        }
        .deep_transform_keys { _1.to_s.camelize(:lower) }
        .compact
      end

      # Private factory method that returns an instance of this class as project items without grouping
      sig do
        params(response: Search::Responses::MemexProjectItemResponse, serializer: SerializerProc)
        .returns(FlatMemexItemsApiResponse)
      end
      def self.build(response, serializer)
        new(
          slices: MemexItemsApiResponse.build_slices(response),
          nodes: serializer.call(response.models),
          page_info: Search::Responses::PageInfo.new(
            start_cursor: response.start_cursor,
            end_cursor: response.end_cursor,
            has_previous_page: response.has_previous_page,
            has_next_page: response.has_next_page
          ),
          total_count: MemexItemsApiResponse::TotalCount.new(value: response.total, is_approximate: response.total_is_approximate?),
        )
      end
    end
  end
end
