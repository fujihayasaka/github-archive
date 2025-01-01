# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class DeleteMigrationArchive < Platform::Mutations::Base
      description "Deletes a migration archive used for GitHub Enterprise Importer (GEI) migrations."
      visibility :public, environments: [:dotcom, :enterprise]
      feature_flag :octoshift_github_owned_storage

      argument :migration_archive_id, ID, "The migration archive ID to delete.", required: true, loads: Objects::MigrationArchive
      field :migration_archive, Objects::MigrationArchive, "The migration archive that was destroyed.", null: true

      def self.async_api_can_modify?(permission, migration_archive:)
        migration_archive.async_organization.then do |organization|
          organization.async_business.then do
            permission.access_allowed?(
              :octoshift_import,
              resource: organization,
              organization: organization,
              current_repo: nil
            )
          end
        end
      end

      def resolve(migration_archive:)
        migration_archive.destroy

        raise Errors::Unprocessable.new(migration_archive.errors.full_messages.join(", ")) if migration_archive.errors.any?

        { migration_archive: migration_archive }
      end
    end
  end
end
