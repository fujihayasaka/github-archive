# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class RemoveOutsideCollaborator < Platform::Mutations::Base
      description "Removes outside collaborator from all repositories in an organization."

      minimum_accepted_scopes ["admin:org"]

      argument :user_id, ID, "The ID of the outside collaborator to remove.", required: true, loads: Objects::User
      argument :organization_id, ID, "The ID of the organization to remove the outside collaborator from.", required: true, loads: Objects::Organization

      field :removed_user, Objects::User, "The user that was removed as an outside collaborator.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, organization:, **inputs)
        org = organization
        permission.access_allowed?(:v4_remove_outside_collaborator, resource: org, organization: org, current_repo: nil, allow_integrations: true, allow_user_via_granular_actor: true)
      end

      def resolve(organization:, user:, **inputs)

        if organization.member?(user)
          raise Errors::Forbidden.new("You cannot specify an organization member to remove as an outside collaborator.")
        elsif organization.user_is_outside_collaborator?(user.id)
          organization.remove_outside_collaborator(user)
          { removed_user: user }
        end
      end
    end
  end
end
