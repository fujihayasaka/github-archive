# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class RestrictedContribution < Objects::Base

      scopeless_tokens_as_minimum

      implements Interfaces::Contribution

      description "Represents a private contribution a user made on GitHub."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, contrib)
        # Restricted contributions are already stripped down to only provide information that's
        # acceptable for anyone to view.
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        # Restricted contributions are already stripped down to only provide information that's
        # acceptable for anyone to view.
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end
    end
  end
end
