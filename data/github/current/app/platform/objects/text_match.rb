# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class TextMatch < Platform::Objects::Base
      description "A text match within a search result."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, text_match)
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

      field :property, String, "The property matched on.", null: false
      field :fragment, String, "The specific text fragment within the property matched on.", null: false
      field :highlights, [Objects::TextMatchHighlight], "Highlights within the matched fragment.", null: false
    end
  end
end
