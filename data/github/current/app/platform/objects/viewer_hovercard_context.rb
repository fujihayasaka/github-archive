# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ViewerHovercardContext < Objects::Base
      implements Interfaces::HovercardContext
      description "A hovercard context with a message describing how the viewer is related."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, ctx)
        # See Platform::Objects::Hovercard#async_api_can_access?
        # To access this non Active Record object the caller already needs to have permissions to the user, issue, or pull request
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        # See Platform::Objects::Hovercard#async_api_can_access?
        # To access this non Active Record object the caller already needs to have permissions to the user, issue, or pull request
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      scopeless_tokens_as_minimum

      field :viewer, Objects::User, "Identifies the user who is related to this context.",
        null: false
    end
  end
end
