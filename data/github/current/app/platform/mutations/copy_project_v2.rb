# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CopyProjectV2 < Platform::Mutations::Base
      description "Copy a project."

      minimum_accepted_scopes ["project"]

      visibility :public, environments: [:dotcom, :enterprise]

      argument :project_id, ID, "The ID of the source Project to copy.", required: true, loads: Objects::ProjectV2
      argument :owner_id, ID, "The owner ID of the new project.", required: true, loads: Unions::OrganizationOrUser
      argument :title, String, "The title of the project.", required: true
      argument :include_draft_issues, Boolean, "Include draft issues in the new project", default_value: false, required: false

      field :project_v2, Objects::ProjectV2, "The copied project.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, owner:, **inputs)
        # An actor can copy if they have read permissions on the source project and
        # project_v2_create permissions on the destination owner.
        # Read permissions for the source project are checked when loading Objects::ProjectV2
        # Write permissions are checked below
        current_org = owner if owner.organization?
        permission.access_allowed?(
          :project_v2_create,
          current_org: current_org,
          owner: owner,
          resource: owner,
          current_repo: nil,
          allow_integrations: true,
          allow_user_via_granular_actor: true,
        )
      end

      def resolve(project:, owner:, title:, include_draft_issues:, **inputs)
        # Create a new target project with the default system fields
        new_project = MemexProject.create_with_associations(
          owner: owner,
          creator: context[:viewer],
          title: title,
          with_default_workflows: false,
          with_mwl_enabled: false,
        )
        raise Platform::Errors::Unprocessable.new(new_project) unless new_project.valid?

        copier_result = MemexProject::Copier.new(
          base_project: project,
          target_project: new_project,
          include_draft_issues: include_draft_issues,
          actor: context[:viewer],
        ).execute

        copy = copier_result.target_project

        if !copy.persisted?
          raise Errors::Unprocessable.new(copy.errors.full_messages.join(", "))
        end

        GlobalInstrumenter.instrument("memex_event",
          {
            actor: context[:viewer],
            memex_project: project,
            name: "copy",
            ui: "graphql",
            memex_project_column: nil,
            memex_project_item: nil,
            context: {
              target_project_id: copy.id,
              target_owner_id: owner.id
            }.to_json,
            memex_project_view: nil,
          }
        )

        { project_v2: copy }
      end
    end
  end
end
