# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ValidationError < Platform::Objects::Base
      description "An error due to invalid inputs to a mutation."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      #
      # Doesn't require special checks here as we have the
      # scopeless_tokens_as_minimum check which just requires
      # the token to be valid
      def self.async_api_can_access?(_permission, _object)
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      #
      # Doesn't require special checks here as we have the
      # scopeless_tokens_as_minimum check which just requires
      # the token to be valid
      def self.async_viewer_can_see?(permission, obj)
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      implements Platform::Interfaces::UserError
      scopeless_tokens_as_minimum

      # All users can see validation errors
      def self.authorized?(*)
        true
      end
    end
  end
end
