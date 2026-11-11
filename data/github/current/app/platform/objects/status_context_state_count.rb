# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class StatusContextStateCount < Platform::Objects::Base
      description "Represents a count of the state of a status context."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, status_context)
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      scopeless_tokens_as_minimum

      field :state, Enums::StatusState, null: false, description: "The state of a status context."
      field :count, Integer, null: false, description: "The number of statuses with this state."
    end
  end
end
