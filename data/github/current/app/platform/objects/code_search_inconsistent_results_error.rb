# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class CodeSearchInconsistentResultsError < Base
      implements Interfaces::CodeSearchError

      description "Indicates that the results returned as part of this response cannot guarantee repo@sha consistency."

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
    end
  end
end
