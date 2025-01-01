# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class RemoveProjectCollaborator < Platform::Mutations::Base
      description "Removes user collaborator from project."
      visibility :internal

      scopeless_tokens_as_minimum

      argument :project_id, ID, "The ID of the project to remove the collaborator from.", required: true, loads: Objects::Project
      argument :user_id, ID, "The ID of the user collaborator to remove from the project.", required: true, loads: Objects::User

      field :project, Objects::Project, "The project that the collaborator was removed from.", null: true
      field :user, Objects::User, "The user collaborator that was removed from the project.", null: true

      def resolve(user:, project:, **inputs)

        if project.owner_type == "Repository"
          raise Errors::Unprocessable.new("Repository projects cannot have collaborators.")
        end

        unless project.adminable_by?(context[:viewer])
          raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have permission to change collaboration settings for this project.")
        end

        if project.members.include?(user) && !context[:viewer].can_have_granular_permissions?
          project.update_user_permission(user, nil)
        end

        { project: project, user: user }
      end
    end
  end
end
