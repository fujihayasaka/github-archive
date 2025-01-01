# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    # See: Search::Aggregations::Percentages
    class LanguageAggregate < Platform::Objects::Base
      description "Represents a programming language found in search results."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, language)
        permission.hidden_from_public?(self) # Update this authorization if we ever go public with this object
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      visibility :internal

      scopeless_tokens_as_minimum

      field :language, Language, "The programming language.", null: false
      field :percentage, Float, "Percent of search results using this language.", null: false
      field :count, Integer, "Number of search results using this language.", null: false
    end
  end
end
