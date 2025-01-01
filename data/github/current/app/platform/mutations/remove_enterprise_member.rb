# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class RemoveEnterpriseMember < Platform::Mutations::Base
      description "Removes a user from all organizations within the enterprise"

      # This mutation can only be run by end-users in the Enterprise Cloud environment.
      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      minimum_accepted_scopes ["admin:enterprise"]

      argument :enterprise_id, ID, "The ID of the enterprise from which the user should be removed.", required: true, loads: Objects::Enterprise
      argument :user_id, ID, "The ID of the user to remove from the enterprise.", required: true, loads: Objects::User

      field :enterprise, Objects::Enterprise, "The updated enterprise.", null: true
      field :user, Objects::User, "The user that was removed from the enterprise.", null: true
      field :viewer, Objects::User, "The viewer performing the mutation.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, enterprise:, **inputs)
        permission.access_allowed?(
          :standard_authorization,
          permission: :manage_enterprise_members,
          resource: enterprise,
          repo: nil,
          organization: nil,
          allow_integrations: true,
          allow_user_via_granular_actor: true,
        )
      end

      def resolve(enterprise:, user:, **inputs)
        ensure_business_can_use_api!(enterprise)
        ensure_business_not_an_emu!(enterprise)

        viewer = context[:viewer]

        begin
          enterprise.remove_member(user, actor: viewer, reason: "removed_via_api")
        rescue Business::ForbiddenRemovalError, Organization::NoAdminsError => err
          raise Errors::Forbidden.new(err.message)
        rescue Business::InvalidRemovalError => err
          raise Errors::Unprocessable.new(err.message)
        end

        {
          enterprise: enterprise,
          user: user,
          viewer: viewer,
        }
      end
    end
  end
end
