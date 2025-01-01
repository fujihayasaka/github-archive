# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class AddProjectCollaborator < Platform::Mutations::Base
      description "Adds user collaborator to project."
      visibility :internal

      scopeless_tokens_as_minimum

      argument :project_id, ID, "The ID of the project to add the collaborator to.", required: true, loads: Objects::Project
      argument :user_id, ID, "The ID of the user collaborator to add to the project.", required: true, loads: Objects::User
      argument :permission, Enums::ProjectPermission, "The permission that the collaborator is being granted on the project.", required: false

      field :project_user_edge, Edges::ProjectUser, "The edge between the project and the user.", null: true

      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, **inputs)
        Platform::Helpers::ProjectDeprecation.ensure_api_availability(permission.viewer)

        super(permission, **inputs)
      end

      def resolve(user:, project:, **inputs)
        if project.owner_type == "Repository"
          raise Errors::Unprocessable.new("Repository projects cannot have collaborators.")
        end

        unless project.adminable_by?(context[:viewer])
          raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have permission to change collaboration settings for this project.")
        end

        if enterprise_managed_user_enabled?(project)
          raise Errors::Unprocessable.new("Projects within IdP managed enterprises cannot have collaborators.")
        end

        if project.members.include?(user)
          raise Errors::Unprocessable.new("#{user.display_login} is already a collaborator on this project.")
        end

        if inputs[:permission] == "none"
          raise Errors::Unprocessable.new("A permission level of 'none' cannot be specified.")
        end

        if violates_2fa_requirement?(project, user)
          raise Errors::Forbidden.new("#{user.display_login} does not meet the organizational 2FA requirements.")
        end

        permission = inputs[:permission] || :read

        # String#to_sym is safe to call here, since we know it's going to be
        # one of the few values in Enum::ProjectPermission.
        project.update_user_permission(user, permission.to_sym) if !context[:viewer].can_have_granular_permissions?

        scope = project.direct_collaborators.order("login ASC")
        connection = Platform::ConnectionWrappers::Relation.new(scope,  parent: project, context: context)

        { project_user_edge: Platform::Models::ProjectUserEdge.new(user, connection) }
      end

      private

      # Private: Check if the owner is enterprise managed
      #
      # project - a project to check
      #
      # Return Boolean
      def enterprise_managed_user_enabled?(project)
        case project.owner_type
        when "User"
          project.owner.is_enterprise_managed?
        when "Organization"
          project.owner.enterprise_managed_user_enabled?
        else
          false
        end
      end

      # Private: Check if the collaborator meets the organization 2fa requirements
      #
      # project - a project to check
      # user - collaborator to be added
      #
      # Return Boolean
      def violates_2fa_requirement?(project, user)
        return false unless project.owner_type == "Organization"

        !project.owner.two_factor_requirement_met_by?(user)
      end
    end
  end
end
