# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class StaffUnarchiveRepository < Platform::Mutations::Base
      description "Allows staff to unarchive a repository."

      visibility :internal
      minimum_accepted_scopes ["site_admin"]

      argument :repository_id, ID, "The ID of the repository to unarchive.", required: true, loads: Objects::Repository

      field :repository, Objects::Repository, "The repository that was unarchived.", null: true

      def self.async_api_can_modify?(permission, repository:)
        viewer_is_site_admin?(permission.viewer, name)
      end

      def resolve(repository:)
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
