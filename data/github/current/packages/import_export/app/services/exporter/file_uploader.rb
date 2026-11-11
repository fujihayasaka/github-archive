# typed: strict
# frozen_string_literal: true

module Exporter
  class FileUploader
    class UploadFailed < StandardError; end

    sig do
      params(
        migration: Migration,
        archive_path: String,
        filename: String,
        content_type: String
      ).void
    end
    def initialize(migration:, archive_path:, filename:, content_type: "application/gzip")
      @migration = migration
      @archive_path = archive_path
      @filename = filename
      @content_type = content_type
    end

    sig { returns(MigrationFile) }
    def upload
      uploader = T.must(@migration.creator)
      migration_file = T.let(nil, T.nilable(MigrationFile))

      ActiveRecord::Base.connected_to(role: :writing) do
        begin
          # Create a MigrationFile record for this archive
          migration_file = MigrationFile.create!(
            migration: @migration,
            uploader: uploader,
            content_type: @content_type,
            name: @filename,
            size: File.size(@archive_path),
            state: :starter,
          )

          # Determine storage policy based on migration settings
          storage_policy = migration_file.storage_policy(actor: uploader)

          # Upload the archive
          perform_upload(migration_file, storage_policy)

          # Mark migration file as uploaded
          migration_file.update!(state: :uploaded)

          migration_file
        rescue => e
          # Clean up migration file if it was created
          begin
            migration_file&.destroy
          rescue
            # Ignore errors during cleanup
          end

          raise UploadFailed, "Failed to upload #{@filename}: #{e.message}"
        end
      end
    end

    private

    sig { params(migration_file: MigrationFile, storage_policy: Storage::Policy).void }
    def perform_upload(migration_file, storage_policy)
      # Use MigrationFileUploader to handle the actual upload
      file_uploader = GitHub::Migrator::MigrationFileUploader.new(
        migration_file: migration_file,
        archive_path: @archive_path,
        storage_policy: storage_policy,
      )

      file_uploader.call
    end
  end
end
