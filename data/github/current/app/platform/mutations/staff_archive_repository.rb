# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class StaffArchiveRepository < Platform::Mutations::Base
      description "Allows staff to mark a repository as archived."

      visibility :internal
      minimum_accepted_scopes ["site_admin"]

      argument :repository_id, ID, "The ID of the repository to mark as archived.", required: true, loads: Objects::Repository

      field :repository, Objects::Repository, "The repository that was marked as archived.", null: true

      def self.async_api_can_modify?(permission, repository:)
        viewer_is_site_admin?(permission.viewer, name)
      end

      def resolve(repository:)
        unless repository.set_archived
          raise Errors::Unprocessable.new("An error occurred when trying to archive repository #{repository.global_relay_id}.")
        end

        {
          repository: FeatureFlag.vexi.enabled?(:repos_domain_reload, default: false) ? Repositories.domain.reload(repository) : repository.reload,
        }
      end

    end
  end
end
