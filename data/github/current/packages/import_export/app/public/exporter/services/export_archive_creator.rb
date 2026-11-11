# typed: strict
# frozen_string_literal: true

module Exporter::Services
  # Service for creating a final export archive from prepared batch files.
  #
  # This service:
  # 1. Uses DirectoryPreparer to download and extract all completed batches
  # 2. Creates a final tar.gz archive from the prepared directory
  #
  # Example usage:
  #   creator = Exporter::Services::ExportArchiveCreator.new(
  #     migration: migration,
  #     archive_path: "/tmp/exports/migration.tar.gz"
  #   )
  #   archive_path = creator.create
  class ExportArchiveCreator
    sig do
      params(
        migration: Migration,
        archive_path: String
      ).void
    end
    def initialize(migration:, archive_path:)
      @migration = migration
      @archive_path = T.let(Pathname.new(archive_path), Pathname)
    end

    sig { void }
    def create
      # Create working directory for extraction in the migration file staging path
      staging_path = GitHub.migration_file_staging_path
      FileUtils.mkdir_p(staging_path) unless File.exist?(staging_path)

      working_dir = Pathname.new(staging_path).join("#{@migration.guid}-work")
      FileUtils.mkdir_p(working_dir)

      begin
        # Prepare directory with all batch files
        prepare_working_directory(working_dir)

        # Write schema version to directory before creating tar.gz
        write_schema_version(working_dir)

        # Write audit log to directory before creating tar.gz
        write_audit_log_to_archive(working_dir)

        # Create the final tar.gz archive
        create_final_archive(working_dir, @archive_path)
      rescue StandardError => e
        GitHub.logger.error(
          "ExportArchiveCreator: Failed to create archive",
          migration_guid: @migration.guid,
          error: e.message,
          backtrace: e.backtrace&.first(5)
        )
        raise
      ensure
        # Clean up working directory
        FileUtils.rm_rf(working_dir) if working_dir.exist?
      end
    end

    private

    # Prepares the working directory by downloading and extracting all batch files.
    #
    # working_dir - Pathname to the working directory
    #
    # Returns nothing.
    sig { params(working_dir: Pathname).void }
    def prepare_working_directory(working_dir)
      preparer = Exporter::DirectoryPreparer.new(
        migration: @migration,
        working_dir: working_dir
      )
      result = preparer.prepare

      GitHub.logger.info(
        "ExportArchiveCreator: Directory preparation complete",
        migration_guid: @migration.guid,
        total_success_count: result[:successful_ids].size,
        total_failed_count: result[:failed_ids].size
      )
    end

    # Creates the final tar.gz archive from the working directory.
    #
    # working_dir - Pathname to the working directory containing files to archive
    # final_archive_path - Pathname to the final archive destination
    #
    # Returns nothing.
    sig { params(working_dir: Pathname, final_archive_path: Pathname).void }
    def create_final_archive(working_dir, final_archive_path)
      archiver = Exporter::ArchiveCreator.new(
        working_dir: working_dir.to_s,
        archive_path: final_archive_path.to_s
      )
      archiver.create

      GitHub.logger.info(
        "ExportArchiveCreator: Created final archive",
        migration_guid: @migration.guid,
        archive_path: final_archive_path.to_s,
        archive_size: File.size(final_archive_path)
      )
    end

    # Writes the current version of gh-migrator's schema to the archive.
    # The schema version allows the migrator to understand what it can and can't
    # import from a given archive.
    #
    # See: GitHub::Migrator::SchemaVersion
    sig { params(working_dir: Pathname).void }
    def write_schema_version(working_dir)
      schema_path = working_dir.join("schema.json")

      writer = Exporter::WriteSchemaVersion.new(
        migration: @migration,
        output_path: schema_path
      )
      writer.call
    end

    # Writes the audit log file to the archive.
    # This will include information about failed batches and processing errors.
    #
    # working_dir - Pathname to the working directory
    #
    # Returns nothing.
    sig { params(working_dir: Pathname).void }
    def write_audit_log_to_archive(working_dir)
      audit_log_path = working_dir.join("audit_log.csv")

      generator = Exporter::GenerateBatchAuditLog.new(
        migration: @migration,
        output_path: audit_log_path
      )
      generator.call
    end
  end
end
