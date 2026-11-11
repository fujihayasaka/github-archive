# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class SetOrganizationInteractionLimit < Platform::Mutations::Base
      description "Set an organization level interaction limit for an organization's public repositories."

      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      minimum_accepted_scopes ["admin:org"]

      argument :organization_id, ID, "The ID of the organization to set a limit for.", required: true, loads: Objects::Organization, as: :org
      argument :limit, Enums::RepositoryInteractionLimit, "The limit to set.", required: true
      argument :expiry, Enums::RepositoryInteractionLimitExpiry, "When this limit should expire.", required: false

      field :organization, Objects::Organization, "The organization that the interaction limit was set for.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, org:, **inputs)
        permission.access_allowed?(:set_organization_interaction_limits,
          resource: org, current_org: org, current_repo: nil,
          allow_integrations: true, allow_user_via_granular_actor: true)
      end

      def resolve(org:, **inputs)
        inputs = {
          object: org,
          limit: inputs[:limit],
          duration: inputs[:expiry] || :one_day,
          actor: context[:viewer],
        }

        result = InteractionLimits::SetInteractionLimit.call(inputs)

        if result.success?
          { organization: result.object }
        else
          raise result.platform_error.new(result.error) # rubocop:disable GitHub/UsePlatformErrors
        end
      end
    end
  end
end
