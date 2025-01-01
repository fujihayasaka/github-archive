# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class CodeSearchRepoFacet < Base
      implements Interfaces::CodeSearchFacet

      description "Refine the search results by an identified repository in the results"

      # The underlying Blackbird API will provide authz for the entire code search object graph.
      def self.async_api_can_access?(_permission, _object)
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      # The underlying Blackbird API will provide authz for the entire code search object graph.
      def self.async_viewer_can_see?(_permission, _object)
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      mobile_only true

      # The underlying Blackbird API will also verify oauth scopes during its authz checks.
      scopeless_tokens_as_minimum

      field :name_with_owner, String, description: "The repository found in the search results", null: false
    end
  end
end
