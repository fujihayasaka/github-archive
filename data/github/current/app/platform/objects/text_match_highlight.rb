# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class TextMatchHighlight < Platform::Objects::Base
      description "Represents a single highlight in a search result match."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, highlight)
        # To access this non Active Record object the caller already need to get permissions for a repo and a commit
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        # To access this non Active Record object the caller already need to get permissions for a repo and a commit
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      scopeless_tokens_as_minimum

      field :text, String, "The text matched.", null: false
      field :begin_indice, Integer, "The indice in the fragment where the matched text begins.", null: false
      field :end_indice, Integer, "The indice in the fragment where the matched text ends.", null: false
    end
  end
end
