# typed: false
# frozen_string_literal: true

module Platform
  module Mutations
    class DeleteProject < Platform::Mutations::Base
      description "Deletes a project."

      minimum_accepted_scopes ["public_repo", "write:org"]

      argument :project_id, ID, "The Project ID to update.", required: true, loads: Objects::Project
      field :owner, Interfaces::ProjectOwner, "The repository or organization the project was removed from.", null: true

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

          permission.access_allowed?(:delete_project, auth_options)
        end
      end

      def resolve(project:, **inputs)
        context[:permission].authorize_content(:project, :destroy, project: project)

        unless project.writable_by?(context[:viewer])
          raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have permission to delete projects on this #{project.owner_type.downcase}.")
        end

        project.enqueue_delete(actor: context[:viewer])

        { owner: project.owner }
      end
    end
  end
end
