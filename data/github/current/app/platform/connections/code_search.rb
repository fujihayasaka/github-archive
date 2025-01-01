# typed: true
# frozen_string_literal: true

module Platform
  module Connections
    class CodeSearch < Connections::Base
      edge_type Objects::CodeSearchResult.edge_type

      total_count_field

      required_capabilities [:mobile_only_schema_mask]

      # This count will be more accurate than the `total_count` field, but will trigger a
      # call to the internal Blackbird Twirp API service. That means if the other fields are used
      # (i.e. nodes, total_count, etc.) and this field is used then a total of two Blackbird
      # API calls are required to fulfill the GraphQL request.
      # If this is null then it means the count request internally failed.
      field :approximate_count, Integer, description: "Approximate number of results", null: true

      field :facets,
        [Unions::CodeSearchFacets],
        description: "Top #{ConnectionWrappers::CodeSearchQuery::FACETS_LIMIT} query facets",
        null: false

      field :errors,
        [Unions::CodeSearchErrors],
        description: "Top #{ConnectionWrappers::CodeSearchQuery::ERRORS_LIMIT} query errors",
        null: false

      field :error_count, Integer, description: "Total number of errors", null: false

      field :facet_count, Integer, description: "Total number of facets", null: false

      # This most likely should be removed before this GraphQL API is made public, but exposing the raw blackbird
      # response might be useful early on for debugging and/or learning about how the internal API works in the wild.
      field :internal_response,
        String,
        description: "Debugging only: JSON serialized internal API response",
        null: false

      def internal_response
        object.internal_response.then do |internal_response|
          internal_response.to_json
        end
      end

      # Same thing with this field as the `internal_response` field above. It is here to help us debug and learn
      # within our production environment. There is no intention here to expose this field to the public nor
      # use it in any way other than for debugging.
      field :internal_count_response,
        String,
        description: "Debugging only: JSON serialized internal API count response",
        null: false

      def internal_count_response
        object.internal_count_response.to_json
      end

      field :limit,
        Integer,
        description: "Debugging only: used to see the calculated limit used for paging",
        null: false

      field :offset,
        Integer,
        description: "Debugging only: used to see the calculated limit used for paging",
        null: false

      field :page,
        Integer,
        description: "Debugging only: used to see the calculated limit used for paging",
        null: false

      field :incomplete,
        Boolean,
        description: "Indicates if the internal API returned a partial result set instead of a timeout",
        null: false,
        method: :incomplete?

      def nodes
        object.edge_nodes
      end
    end
  end
end
