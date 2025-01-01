# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class RepositoryInteractionAbility < Platform::Objects::Base
      description "Repository interaction limit that applies to this object."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, ability)
        interactable = ability.interactable

        if ability.interaction_ability.organization?
          permission.access_allowed?(
            :read_organization_interaction_limits,
            resource: interactable,
            current_repo: nil,
            current_org: interactable,
            allow_integrations: true,
            allow_user_via_granular_actor: true
          )
        elsif ability.interaction_ability.user?
          permission.access_allowed?(
            :read_user_interaction_limits,
            resource: interactable,
            current_repo: nil,
            current_org: nil,
            allow_integrations: false,
            allow_user_via_granular_actor: true,
            installation_required: false
          )
        else
          permission.async_owner_if_org(interactable).then do |org|
            permission.access_allowed?(
              :read_repository_interaction_limits,
              resource: interactable,
              current_repo: interactable,
              current_org: org,
              allow_integrations: true,
              allow_user_via_granular_actor: true
            )
          end
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        object.interactable.async_can_read_interaction_limits?(permission.viewer)
      end

      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      minimum_accepted_scopes ["admin:org", "read:user", "public_repo"]

      field :limit, Enums::RepositoryInteractionLimit, description: "The current limit that is enabled on this object.", null: false

      def limit
        @object.interaction_ability.async_overall_active_limit
      end

      field :origin, Enums::RepositoryInteractionLimitOrigin, description: "The origin of the currently active interaction limit.", null: false

      def origin
        @object.interaction_ability.async_active_limit_origin
      end

      field :expires_at, Scalars::DateTime, description: "The time the currently active limit expires.", null: true

      def expires_at
        @object.interaction_ability.async_overall_active_limit_expiry
      end
    end
  end
end
