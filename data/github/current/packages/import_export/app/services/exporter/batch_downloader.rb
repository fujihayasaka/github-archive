# typed: strict
# frozen_string_literal: true

module Exporter
  # Service class to download a migration export batch file from storage.
  #
  # - Downloads the batch's migration file from blob storage to a temporary file
  # - Returns the path to the downloaded file for further processing
  #
  class BatchDownloader
    include GitHub::Migrator::DownloadHelpers

    sig { returns(MigrationExportBatch) }
    attr_reader :batch

    sig { returns(User) }
    attr_reader :actor

    sig { params(batch: MigrationExportBatch, actor: User).void }
    def initialize(batch:, actor:)
      @batch = T.let(batch, MigrationExportBatch)
      @actor = T.let(actor, User)
    end

    # Download the batch file to a temporary file.
    # Returns the path to the downloaded file, or nil if the batch has no migration_file.
    # Caller is responsible for cleaning up the returned file.
    sig { returns(T.nilable(String)) }
    def download
      migration_file = batch.migration_file
      return unless migration_file

      temp_file = Tempfile.new(["batch-", ".tar.gz"])
      temp_file.close

      download_file(migration_file, T.must(temp_file.path))

      # Track the download
      migration_file.download

      temp_file.path
    end

    private

    # Download the migration file to a local path
    sig { params(migration_file: MigrationFile, destination_path: String).void }
    def download_file(migration_file, destination_path)
      url = migration_file.download_url(actor: actor)

      GitHub.logger.info(
        "Downloading batch file",
        migration_guid: T.must(batch.migration).guid,
        batch_id: batch.id,
        model_type: batch.model_type,
        type: batch.type
      )

      success, status_code = save_from_url(url: url, to: destination_path)

      unless success
        raise "Failed to download batch file (HTTP #{status_code}) for migration_guid=#{T.must(batch.migration).guid}, batch_id=#{batch.id}"
      end
    end
  end
end
