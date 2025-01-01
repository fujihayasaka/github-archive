# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class CodeSearchLanguageFacet < Base
      implements Interfaces::CodeSearchFacet

      description "Refine the search results by an identified language in the results"

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

      field :color, String, description: "Identifiable color used for the language", null: false

      field :name, String, description: "Name of the language", null: false
    end
  end
end
