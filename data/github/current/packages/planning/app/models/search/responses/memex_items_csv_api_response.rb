# typed: strict
# frozen_string_literal: true

# This class represents a CSV response that we can return from our internal API endpoints to the Projects web
# client.
#
# Instances of this class should be created via the `build_csv` factory method. That method will execute the query it is
# given against Elasticsearch, and then return an instance of this class, which wraps the Elasticsearch response with
# pagination information that is styled after GraphQL: https://graphql.org/learn/pagination/. That instance of this
# class can then be serialized to CSV with the `to_csv` method.
#
# EXAMPLE:
#
#   response = MemexItemsApiResponse.build_csv(query:, serializer:)
#   self.response_body = response.to_csv
module Search
  module Responses
    class MemexItemsCsvApiResponse < T::Struct

      # A serialized page of ungrouped items in CSV format
      const :rows, T::Array[String]

      # Information about this page of items.
      const :page_info, Search::Responses::PageInfo, default: Search::Responses::PageInfo.new

      # Information about the total number of items in a given project independent of page size.
      const :total_count, Search::Responses::TotalCount

      # Returns a Hash representation of this response that can be passed as the `json` key to
      # the `render` method of a Rails controller.
      sig { returns(T::Hash[String, T.untyped]) }
      def to_hash
        {
          rows:,
          pageInfo: page_info.to_hash,
          totalCount: total_count.to_hash,
        }
        .deep_transform_keys { _1.to_s.camelize(:lower) }
        .compact
      end

      # Private factory method that returns an instance of this class as project items without grouping
      sig do
        params(response: Search::Responses::MemexProjectItemResponse, serializer: MemexItemsApiResponse::CSVSerializerProc)
        .returns(MemexItemsCsvApiResponse)
      end
      def self.build(response, serializer)
        new(
          rows: serializer.call(response),
          page_info: Search::Responses::PageInfo.new(
            start_cursor: response.start_cursor,
            end_cursor: response.end_cursor,
            has_previous_page: response.has_previous_page,
            has_next_page: response.has_next_page
          ),
          total_count: Search::Responses::TotalCount.new(value: response.total, is_approximate: response.total_is_approximate?),
        )
      end
    end
  end
end
