# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UnlinkRepositoryFromProject < Platform::Mutations::Base
      description "Deletes a repository link from a project."

      # This scope someday needs to be changed to a Projects-specific scope!
      # Any user with admin access on a project can link *any repo* under the same
      # top-level owner, provided they have read access to that repo.
      # Project read requires a `repo` scope (`public_repo` is not sufficient)
      minimum_accepted_scopes ["repo"]

      argument :project_id, ID, "The ID of the Project linked to the Repository.", required: true, loads: Objects::Project
      argument :repository_id, ID, "The ID of the Repository linked to the Project.", required: true, loads: Objects::Repository
      field :project, Objects::Project, "The linked Project.", null: true
      field :repository, Objects::Repository, "The linked Repository.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, project:, **inputs)
        Platform::Helpers::ProjectDeprecation.ensure_api_availability(permission.viewer)

        project.async_owner.then do |owner|
          org = nil
          org = owner if owner.is_a?(::Organization)

          permission.access_allowed?(:project_repository_links_write,
            resource: project,
            current_org: org,
            allow_integrations: true,
            allow_user_via_granular_actor: true,
            current_repo: inputs[:repository],
          )
        end
      end

      def resolve(repository:, project:, **inputs)
        context[:permission].authorize_content(:project, :update, project: project)

        unless project.writable_by?(context[:viewer])
          raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have permission to delete repository links from this project.")
        end

        unless repository.readable_by?(context[:viewer]) || context[:viewer].can_have_granular_permissions?
          raise Errors::NotFound.new("Repository not found.")
        end

        project.unlink_repository(repository)

        {
          project: project,
          repository: repository,
        }
      end
    end
  end
end
