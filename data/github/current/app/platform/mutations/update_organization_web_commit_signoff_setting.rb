# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateOrganizationWebCommitSignoffSetting < Platform::Mutations::Base
      description "Sets whether contributors are required to sign off on web-based commits for repositories in an organization."

      minimum_accepted_scopes ["admin:org"]

      argument :organization_id, ID, "The ID of the organization on which to set the web commit signoff setting.", required: true, loads: Objects::Organization
      argument :web_commit_signoff_required, Boolean, "Enable signoff on web-based commits for repositories in the organization?", required: true

      field :organization, Objects::Organization, "The organization with the updated web commit signoff setting.", null: true

      field :message, String, "A message confirming the result of updating the web commit signoff setting.", null: true

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
          allow_user_via_granular_actor: true
        )
      end

      def resolve(organization:, **inputs)
        viewer = context[:viewer]
        web_commit_signoff_required = inputs[:web_commit_signoff_required]

        if web_commit_signoff_required
          organization.enable_dco_signoff_for_all(actor: viewer)
          message = "Web commit signoff is now enabled for #{organization.name}."
        else
          organization.reset_dco_signoff_for_all(actor: viewer)
          message = "Web commit signoff is now disabled for #{organization.name}."
        end

        {
          organization: organization,
          message: message,
        }
      end
    end
  end
end
