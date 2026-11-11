# typed: strict
# frozen_string_literal: true

module Exporter
  # Service for writing the schema version file to the archive.
  #
  # The schema version allows the migrator to understand what it can and can't
  # import from a given archive.
  #
  # See: GitHub::Migrator::SchemaVersion
  class WriteSchemaVersion
    MAX_RETRIES = 5

    sig do
      params(
        migration: Migration,
        output_path: Pathname
      ).void
    end
    def initialize(migration:, output_path:)
      @migration = migration
      @output_path = output_path
    end

    sig { void }
    def call
      # Check if any batches contain attachments
      has_attachments = ConnectionRetry.with_retry(
        migration: @migration,
        query_name: :check_attachment_batches
      ) do
        MigrationExportBatch.throttle_with_retry(max_retry_count: MAX_RETRIES) do
          MigrationExportBatch
            .where(migration_id: @migration.id, model_type: "attachment")
            .exists?
        end
      end

      # Determine schema version based on content
      schema_version_string = if has_attachments
        GitHub::Migrator::SchemaVersion::ATTACHABLE
      else
        GitHub::Migrator::SchemaVersion::WIKI
      end

      File.open(@output_path, "w") do |file|
        info = {
          version: schema_version_string,
          github_sha: GitHub.current_sha,
        }
        file.write(info.to_json)
      end
    end
  end
end
