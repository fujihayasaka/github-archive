# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class Achievable < Platform::Objects::Base
      description "A kind of Achievement that may be earned by users."

      mobile_only true

      scopeless_tokens_as_minimum

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, _object)
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      field :name, String, null: false, method: :display_name,
        description: "This achievable's display name in a human-readable format."

      field :slug, String, null: false,
        description: "URL-friendly string used to identify this achievable."

      field :highest_tier_number, Integer, null: false,
        description: "Highest potentially attainable tier for achievements of this kind, one-indexed."

      def highest_tier_number
        # highest_tier is zero-indexed
        object.highest_tier + 1
      end
    end
  end
end
