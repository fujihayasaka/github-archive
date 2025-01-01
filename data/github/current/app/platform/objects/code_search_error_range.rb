# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class CodeSearchErrorRange < Base
      description "A positional character range of a code search query that caused an error"

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

      field :start_position, Integer, description: "Starting index of the query which caused the error", null: false

      field :end_position, Integer, description: "Ending index of the query which caused the error", null: false
    end
  end
end
