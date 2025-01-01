# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class CodeSearchPathFacet < Base
      implements Interfaces::CodeSearchFacet

      description "Refine the search results by an identified path in the results"

      # The underlying Blackbird API will provide authz for the entire code search object graph.
      def self.async_api_can_access?(_permission, _object)
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      # The underlying Blackbird API will provide authz for the entire code search object graph.
      def self.async_viewer_can_see?(_permission, _object)
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      required_capabilities [:mobile_only_schema_mask]

      # The underlying Blackbird API will also verify oauth scopes during its authz checks.
      scopeless_tokens_as_minimum

      field :path, String, description: "Path found in the results", null: false
    end
  end
end
