# typed: false
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateProject < Platform::Mutations::Base
      description "Updates an existing project."

      minimum_accepted_scopes ["public_repo", "write:org"]

      argument :project_id, ID, "The Project ID to update.", required: true, loads: Objects::Project
      argument :name, String, "The name of project.", required: false
      argument :body, String, "The description of project.", required: false
      argument :state, Enums::ProjectState, "Whether the project is open or closed.", required: false
      argument :public, Boolean, "Whether the project is public or not.", required: false
      argument :organization_permission, Enums::ProjectPermission, "The permission that all members of the owning organization have on this project.", required: false

      field :project, Objects::Project, "The updated project.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, project:, **inputs)
        auth_options = {
          resource: project,
          current_org: nil,
          allow_integrations: true,
          allow_user_via_granular_actor: true,
        }

        project.async_owner.then do |project_owner|
          auth_options[:owner] = project_owner

          if project_owner.is_a?(::Organization)
            auth_options[:organization] = project_owner
            auth_options[:current_org] = project_owner
            auth_options[:current_repo] = nil
          elsif project_owner.is_a?(::Repository)
            auth_options[:current_repo] = project_owner
          elsif project_owner.is_a?(::User)
            auth_options[:current_repo] = nil
          end

          permission.access_allowed?(:update_project, auth_options)
        end
      end

      def resolve(project:, **inputs)
        validate_request!(context[:viewer], project, inputs, context[:permission])

        if inputs.key?(:organization_permission)
          permission = if inputs[:organization_permission] == "none"
            nil
          else
            inputs[:organization_permission].downcase.to_sym
          end

          project.update_org_permission(permission)
        end

        case inputs[:state]
        when "open"
          project.open if project.closed?
        when "closed"
          project.close if project.open?
        end

        project.name = inputs[:name] if inputs.key?(:name)
        project.body = inputs[:body] if inputs.key?(:body)
        project.public = inputs[:public] if inputs.key?(:public)

        if project.save
          { project: project }
        else
          raise Errors::Unprocessable.new(project.errors.full_messages.join(", "))
        end
      end

      private def validate_request!(viewer, project, inputs, content_authorizer)
        content_authorizer.authorize_content(:project, :update, project: project)

        unless project.writable_by?(viewer)
          raise Errors::Forbidden.new("#{viewer.display_login} does not have permission to update this project.")
        end

        validate_visibility_change!(viewer, project, inputs)
        validate_org_permission_change!(viewer,  project, inputs)

        nil
      end

      private def validate_visibility_change!(viewer, project, inputs)
        return unless inputs.key?(:public)

        # EMUs can't have resources with public visibility
        if inputs[:public].present? && !Project.owner_can_have_public_projects?(project.owner)
          raise Errors::Forbidden.new("Public visibility is not supported for enterprise managed projects.")
        end

        if project.owner_type == "Repository"
          raise Errors::Unprocessable.new("Visibility cannot be updated on repository projects.")
        end

        unless project.viewer_can_change_visibility?(viewer)
          raise Errors::Forbidden.new("#{viewer.display_login} does not have permission to update this project's visibility.")
        end

        nil
      end

      private def validate_org_permission_change!(viewer, project, inputs)
        return unless inputs.key?(:organization_permission)

        if project.owner_type != "Organization"
          raise Errors::Unprocessable.new("Organization-wide permissions cannot be updated on #{project.owner_type.downcase} projects.")
        end

        unless project.owner.member?(viewer)
          raise Errors::Forbidden.new("#{viewer.display_login} must be a member of the #{project.owner.display_login} organization to modify its projects' organization-wide permissions.")
        end

        unless project.adminable_by?(viewer)
          raise Errors::Forbidden.new("#{viewer.display_login} does not have permission to update this project's organization-wide permissions.")
        end

        nil
      end
    end
  end
end
