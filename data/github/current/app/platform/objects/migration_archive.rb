# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class MigrationArchive < Platform::Objects::Base
      description "An archive to be used for GitHub Enterprise Importer (GEI) migrations."
      visibility :public, environments: [:dotcom, :enterprise]
      model_name "OctoshiftMigrationArchive"
      feature_flag :octoshift_github_owned_storage

      scopeless_tokens_as_minimum

      field :guid, String, "The GUID of the migration archive.", null: false
      field :name, String, "The name of the migration archive.", null: false
      field :size, Integer, "The size of the migration archive, in bytes.", null: false
      field :uri, Scalars::URI, "The GEI URI of the migration archive.", method: :gei_uri, null: false
      field :organization, Objects::Organization, "The organization of the migration archive.", null: false
      field :created_at, Scalars::DateTime, "The date and time the migration archive was created.", null: false

      implements_node templates: [
        [:ma, :guid]
      ], as: "MA", uses_database_id: false, ready_date: Platform::Helpers::GlobalId::COHORT_5 do |octoshift_migration_archive|
        {
          prefix: :ma,
          guid: octoshift_migration_archive.guid
        }
      end

      def self.load_from_global_id(guid)
        Loaders::ActiveRecord.load(::OctoshiftMigrationArchive, guid, column: :guid)
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, octoshift_migration_archive)
        octoshift_migration_archive.async_organization.then do |organization|
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

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, octoshift_migration_archive)
        octoshift_migration_archive.async_organization.then do |organization|
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
    end
  end
end
