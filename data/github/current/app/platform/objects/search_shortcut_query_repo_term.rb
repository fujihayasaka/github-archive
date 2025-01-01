# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class SearchShortcutQueryRepoTerm < Platform::Objects::Base
      description "Known repository term and value extracted from a search shortcut query string"
      scopeless_tokens_as_minimum
      mobile_only true

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      implements Interfaces::SearchShortcutQueryBasicTerm
      implements Interfaces::SearchShortcutQueryParsedTerm

      field :repository, Objects::Repository, "The repository referenced in this term", null: true

      def repository
        return nil unless object[:value]

        Loaders::RepositoryByNwo.load(object[:value]).then do |repo|
          next unless repo
          Platform::Security::RepositoryAccess.async_guard(repo, security_violation_behaviour: :nil)
        end
      end
    end
  end
end
