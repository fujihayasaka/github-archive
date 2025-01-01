# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UnlinkProjectV2FromRepository < Platform::Mutations::Base
      description "Unlinks a project from a repository."

      minimum_accepted_scopes ["public_repo", "read:project"]

      visibility :public, environments: [:dotcom, :enterprise]

      argument :project_id, ID, "The ID of the project to unlink from the repository.", required: true, loads: Objects::ProjectV2
      argument :repository_id, ID, "The ID of the repository to unlink from the project.", required: true, loads: Objects::Repository

      field :repository, Objects::Repository, "The repository the project is no longer linked to.", null: true

      def self.async_api_can_modify?(permission, project:, repository:)
        unless GitHub.projects_new_enabled?
          raise Errors::Unprocessable::ProjectsNewDisabled.new
        end

        project.async_owner.then do |owner|
          project_org = owner if owner.organization?

          permission.async_owner_if_org(repository).then do |repo_org|
            permission.access_allowed?(
              :project_v2_read,
              current_org: project_org,
              resource: project,
              current_repo: repository,
              allow_integrations: true,
              allow_user_via_granular_actor: true
            ) &&
            permission.access_allowed?(
              :write_file,
              current_org: repo_org,
              resource: repository,
              current_repo: repository,
              allow_integrations: true,
              allow_user_via_granular_actor: true
            )
          end
        end
      end

      def resolve(project:, repository:)
        validate(project, repository)
        link = MemexProjectLink.find_by(source: repository, memex_project: project)
        return { repository: repository } unless link

        result = link.destroy
        return { repository: repository } if result

        raise Errors::Unprocessable.new(link.errors.full_messages.join(", "))
      end

      def validate(project, repository)
        raise Errors::NotFound.new("Project not found.") unless project && project.readable_by?(context[:viewer])
        raise Errors::Forbidden.new("You must have write access on this repository.") unless repository.pushable_by?(context[:viewer])
        raise Errors::Validation.new("The project owner and the repository owner must be the same.") unless project.owner == repository.owner
      end
    end
  end
end
