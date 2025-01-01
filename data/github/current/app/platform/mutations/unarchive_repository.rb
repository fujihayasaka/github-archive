# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UnarchiveRepository < Platform::Mutations::Base
      description "Unarchives a repository."

      minimum_accepted_scopes ["public_repo"]

      argument :repository_id, ID, "The ID of the repository to unarchive.", required: true, loads: Objects::Repository

      field :repository, Objects::Repository, "The repository that was unarchived.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, repository:)
        permission.async_owner_if_org(repository).then do |org|
          permission.access_allowed?(
            :edit_repo,
            repo: repository,
            resource: repository,
            current_org: org,
            allow_integrations: true,
            allow_user_via_granular_actor: true,
          )
        end
      end

      def resolve(repository:)
        if !repository.resources.administration.writable_by?(context[:viewer])
          message = "#{context[:viewer].display_login} does not have permission to unarchive repository #{repository.global_relay_id}."
          raise Errors::Forbidden.new(message)
        end

        if repository.unarchive_blocked?
          raise Errors::Unprocessable.new("Repository #{repository.global_relay_id} cannot be unarchived because its parent organization is archived.")
        end

        unless repository.unset_archived
          raise Errors::Unprocessable.new("An error occurred when trying to unarchive repository #{repository.global_relay_id}.")
        end

        {
          repository: repository.reload,
        }
      end
    end
  end
end
