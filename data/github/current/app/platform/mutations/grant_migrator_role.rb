# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class GrantMigratorRole < Platform::Mutations::Base
      description "Grant the migrator role to a user or a team."

      ROLE_NAME = "octoshift_migrator"
      private_constant :ROLE_NAME

      minimum_accepted_scopes ["admin:org"]

      argument :organization_id, ID, "The ID of the organization that the user/team belongs to.", required: true, loads: Objects::Organization
      argument :actor, String, "The user login or Team slug to grant the migrator role.", required: true
      argument :actor_type, Enums::ActorType, "Specifies the type of the actor, can be either USER or TEAM.", required: true

      field :success, Boolean, "Did the operation succeed?", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, organization:, **inputs)
        permission.access_allowed?(
          :octoshift_admin,
          resource: organization,
          organization: organization,
          current_repo: nil
        )
      end

      def resolve(organization:, **inputs)
        begin
          role_grant_result = Octoshift::AuthorizationPolicy.grant_octoshift_migrator!(
            actor_type: inputs[:actor_type],
            actor: inputs[:actor],
            organization: organization
          )
        rescue Octoshift::AuthorizationPolicy::RoleGranterError, Octoshift::AuthorizationPolicy::UserDoesNotBelongToOrgError => e
          raise Errors::Forbidden.new(e.message)
        rescue Octoshift::AuthorizationPolicy::ActorNotFoundError => e
          raise Errors::NotFound.new(e.message)
        end

        { success: role_grant_result.success? }
      end
    end
  end
end
