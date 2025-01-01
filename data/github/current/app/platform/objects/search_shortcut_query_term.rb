# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class SearchShortcutQueryTerm < Platform::Objects::Base
      description "Known term and value extracted from a search shortcut query string"
      scopeless_tokens_as_minimum
      mobile_only true

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      #
      # This `object` is a Hash. Authorization and nilification is handled by the parent object and field resolvers.
      def self.async_api_can_access?(permission, object)
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      #
      # This `object` is a Hash. Authorization and nilification is handled by the parent object and field resolvers.
      def self.async_viewer_can_see?(permission, object)
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      implements Interfaces::SearchShortcutQueryBasicTerm
      implements Interfaces::SearchShortcutQueryParsedTerm
    end
  end
end
