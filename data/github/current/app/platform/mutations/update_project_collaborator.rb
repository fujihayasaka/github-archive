# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateProjectCollaborator < Platform::Mutations::Base
      description "Updates the permission the user collaborator has on the project."
      visibility :internal

      scopeless_tokens_as_minimum

      argument :project_id, ID, "The ID of the project to update the permission on.", required: true, loads: Objects::Project
      argument :user_id, ID, "The ID of the user collaborator to update the permission for.", required: true, loads: Objects::User
      argument :permission, Enums::ProjectPermission, "The permission that the collaborator should have on the project.", required: true

      field :project, Objects::Project, "The project that the collaborator is on.", null: true
      field :user, Objects::User, "The user collaborator that is on the project.", null: true

      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, **inputs)
        Platform::Helpers::ProjectDeprecation.ensure_api_availability(permission.viewer)

        super(permission, **inputs)
      end

      def resolve(user:, project:, **inputs)
        raise Errors::Unprocessable.new("A permission level of 'none' cannot be specified.") if inputs[:permission] == "none"

        if project.owner_type == "Repository"
          raise Errors::Forbidden.new("Repository projects cannot have collaborators.")
        end

        unless project.adminable_by?(context[:viewer])
          raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have permission to change collaboration settings for this project.")
        end

        if project.members.exclude?(user)
          raise Errors::Unprocessable.new("#{user.display_login} is not a collaborator on this project.")
        end

        # String#to_sym is safe to call here, since we know it's going to be
        # one of the few values in Enum::ProjectPermission.
        project.update_user_permission(user, inputs[:permission].to_sym) if !context[:viewer].can_have_granular_permissions?

        { project: project, user: user }
      end
    end
  end
end
