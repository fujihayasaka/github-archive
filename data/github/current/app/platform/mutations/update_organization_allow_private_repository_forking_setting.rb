# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateOrganizationAllowPrivateRepositoryForkingSetting < Platform::Mutations::Base
      description "Sets whether private repository forks are enabled for an organization."

      minimum_accepted_scopes ["admin:org"]

      argument :organization_id, ID, "The ID of the organization on which to set the allow private repository forking setting.", required: true, loads: Objects::Organization
      argument :forking_enabled, Boolean, "Enable forking of private repositories in the organization?", required: true

      field :organization, Objects::Organization, "The organization with the updated allow private repository forking setting.", null: true

      field :message, String, "A message confirming the result of updating the allow private repository forking setting.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, organization:, **inputs)
        org = organization
        permission.access_allowed?(:update_org,
          resource: org,
          current_repo: nil,
          current_org: org,
          allow_integrations: true,
          allow_user_via_granular_actor: true,
          user: permission.viewer
        )
      end

      def resolve(organization:, **inputs)
        viewer = context[:viewer]
        forking_enabled = inputs[:forking_enabled]

        if organization&.business&.allow_private_repository_forking_policy?
          raise Errors::Forbidden.new("Forking policy has been set by enterprise administrators.")
        end

        if forking_enabled
          organization.allow_private_repository_forking(actor: viewer)
          message = "Private repository forking is now enabled for #{organization.name}."
        else
          organization.block_private_repository_forking(actor: viewer)
          message = "Private repository forking is now disabled for #{organization.name}."
        end

        {
          organization: organization,
          message: message,
        }
      end
    end
  end
end
