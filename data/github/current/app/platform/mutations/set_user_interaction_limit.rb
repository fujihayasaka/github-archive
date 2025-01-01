# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class SetUserInteractionLimit < Platform::Mutations::Base
      description "Set a user level interaction limit for an user's public repositories."

      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      minimum_accepted_scopes ["user"]

      argument :user_id, ID, "The ID of the user to set a limit for.", loads: Objects::User, required: true
      argument :limit, Enums::RepositoryInteractionLimit, "The limit to set.", required: true
      argument :expiry, Enums::RepositoryInteractionLimitExpiry, "When this limit should expire.", required: false

      field :user, Objects::User, "The user that the interaction limit was set for.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, user:, **inputs)
        permission.access_allowed?(:write_user_interaction_limits,
          resource: user, current_org: nil, current_repo: nil,
          allow_integrations: false, allow_user_via_granular_actor: true, installation_required: false)
      end

      def resolve(user:, **inputs)
        inputs = {
          object: user,
          limit: inputs[:limit],
          duration: inputs[:expiry] || :one_day,
          actor: context[:viewer],
        }

        result = InteractionLimits::SetInteractionLimit.call(inputs)

        if result.success?
          { user: result.object }
        else
          raise result.platform_error.new(result.error) # rubocop:disable GitHub/UsePlatformErrors
        end
      end
    end
  end
end
