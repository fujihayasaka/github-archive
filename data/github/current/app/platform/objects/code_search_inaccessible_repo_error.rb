# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class CodeSearchInaccessibleRepoError < Base
      implements Interfaces::CodeSearchError

      description "Missing or inaccessible repository or organization"

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

      # In some cases, the repository may not exist or the actor might not have access to, so in those
      # cases we still want to return what the repository owner/name that was trying to be searched was.
      # We are not exposing anything sensitive here as the name with owner should be what the caller inputted
      # into the query and we are simply relay that back to them.
      field :name_with_owner, String, description: "The repository trying to be searched", null: false

      field :ranges, [Objects::CodeSearchErrorRange], description: "Ranges of the query which cause the error", null: false
    end
  end
end
