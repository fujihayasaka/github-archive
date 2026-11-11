# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module Migration
      include Platform::Interfaces::Base

      description "Represents a GitHub Enterprise Importer (GEI) migration."

      field :id, ID, description: "The Node ID of the Migration object", method: :global_relay_id, null: false

      field :repository_name, String, "The target repository name.", null: false

      field :migration_source, Objects::MigrationSource, "The migration source.", null: false

      field :source_url, Platform::Scalars::URI, "The migration source URL, for example `https://github.com` or `https://monalisa.ghe.com`.", null: false

      field :state, Enums::MigrationState, description: "The migration state.", null: false

      field :failure_reason, String, "The reason the migration failed.", null: true

      field :continue_on_error, Boolean, "The migration flag to continue on error.", null: false

      field :migration_log_url, Platform::Scalars::URI, "The URL for the migration log (expires 1 day after migration completes).", null: true

      field :warnings_count, Integer, description: "The number of warnings encountered for this migration. To review the warnings, check the [Migration Log](" \
        "https://docs.github.com/migrations/using-github-enterprise-importer/completing-your-migration-with-github-enterprise-importer/accessing-your-migration-logs-for-github-enterprise-importer).",
        null: false

      field :database_id, String, "Identifies the primary key from the database.", null: true

      created_at_field

      def self.load_from_global_id(migration_id, use_staging: false, use_review_lab: false, use_load_testing: false)
        connection_builder = if use_staging
          Octoshift::Twirp::ConnectionBuilder.staging
        elsif use_review_lab
          Octoshift::Twirp::ConnectionBuilder.review_lab
        elsif use_load_testing
          Octoshift::Twirp::ConnectionBuilder.load_testing
        else
          Octoshift::Twirp::ConnectionBuilder.new
        end

        migration_client = Octoshift::Twirp::MigrationClient.new(faraday_connection: connection_builder.build)

        begin
          migration_response = migration_client.get_migration(migration_id: migration_id)
        rescue Octoshift::Twirp::Error => e
          if e.message.include?("not found")
            raise Errors::NotFound.new("Migration not found. This means that the ID you provided is invalid or the migration has been automatically deleted 7 days after it was created.")
          else
            raise Errors::Unprocessable.new(e.message)
          end
        end

        Platform::Objects::MigrationSource.load_migration_source(
          migration_response.source_connector_id,
          use_staging: use_staging,
          use_review_lab: use_review_lab,
          use_load_testing: use_load_testing
        ).then do |migration_source|
          Octoshift::RepositoryMigration.new(migration_response, migration_source)
        end
      end
    end
  end
end
