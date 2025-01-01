# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateOrganizationWideProjectsV2Role < Platform::Mutations::Base
      description "Updates Projects base permissions for an organization."

      minimum_accepted_scopes ["admin:org"]
      feature_flag :org_wide_projects_v2_role_mutation

      argument :organization_id, ID, "The ID of the organization to update.", required: true, loads: Objects::Organization
      argument :role, Platform::Enums::ProjectV2Roles, "The new role to set for the organization-wide projects.", required: true

      field :organization, Objects::Organization, "The organization with the updated projects role.", null: true
      field :errors, [String], "Errors encountered during the update.", null: false

      # Determine whether the viewer can access this mutation via the API (called internally).
      def self.async_api_can_modify?(permission, organization:, **inputs)
        permission.access_allowed?(:update_org,
          resource: organization,
          current_repo: nil,
          current_org: organization,
          allow_integrations: true,
          allow_user_via_granular_actor: true
        )
      end

      def resolve(organization:, **inputs)
        viewer = context[:viewer]
        role = inputs[:role]

        unless viewer.feature_flag_enabled?(:org_wide_projects_v2_role_mutation, default: false)
          raise Errors::Forbidden.new("#{viewer.display_login} is not authorized to perform this action.")
        end

        organization.update_organization_wide_projects_role(role, viewer)
        { organization:, errors: [] }
      rescue ArgumentError
        { organization: nil, errors: ["Can't update permissions"] }
      end
    end
  end
end
