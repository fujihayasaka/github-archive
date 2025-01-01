# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class RepositoryFileImporter < Importer
      include GitHub::Migrator::TarUtils

      class InvalidTarballUrl < StandardError; end

      REPO_FILE_URL_REGEXP = %r{\Atarball://root/repository_files/(?<id>\d+)/(?!\.\.$|\.$)(?<basename>[^/]+)\z}.freeze

      def import(attributes, options = {})
        file_asset_path = get_file_asset_path(attributes["file_url"])

        repository_file = RepositoryFile.new do |repository_file|
          repository_file.uploader = model_from_source_url!(attributes["user"]) || User.ghost
          repository_file.repository = model_from_source_url!(attributes["repository"])
          repository_file.name = attributes["file_name"]
          repository_file.content_type = attributes["file_content_type"]
          repository_file.created_at = attributes["created_at"]
        end

        raise_on_unsupported_asset!(file_asset_path)

        tmp_file = read_file_from_archive(file_asset_path)

        asset_file = ActionDispatch::Http::UploadedFile.new(
          filename: attributes["file_name"],
          tempfile: tmp_file,
          type: attributes["file_content_type"],
        )

        ImporterResult.new(
          import_asset(repository_file, asset_file)
        )
      rescue GitHub::Migrator::UnsupportedUploadableAsset => error
        log_and_create_importer_result(
          attributes,
          error,
          "Skipped import: unsupported uploadable asset",
          "repository_file",
          "skipped"
        )
      rescue GitHub::Migrator::AssociationFailed => error
        log_and_create_importer_result(
          attributes,
          error,
          "Skipped import: failed to find model associated with repository file",
          "repository_file",
          "skipped"
        )
      rescue ActiveRecord::NotNullViolation,
             ActiveRecord::RecordInvalid => error
        log_and_create_importer_result(
          attributes,
          error,
          "Skipped import: invalid or missing repository file",
          "repository_file",
          "skipped"
        )
      rescue GitHub::Storage::Uploader::Error,
        ::Storage::Policy::HttpError => error
        log_and_create_importer_result(
          attributes,
          error,
          "Skipped import: repository file upload failed",
          "repository_file",
          "skipped"
        )
      rescue Errno::ENOENT => error
        log_and_create_importer_result(
          attributes,
          error,
          "Skipped import: failed to find repository file in archive",
          "repository_file",
          "skipped"
        )
      rescue InvalidTarballUrl => error
        log_and_create_importer_result(
          attributes,
          error,
          "Skipped import: #{error.message}",
          "repository_file",
          "skipped"
        )
      ensure
        tmp_file.close if file_asset_path && File.exist?(file_asset_path)
      end

      private

      def get_file_asset_path(file_url)
        file_url_match = REPO_FILE_URL_REGEXP.match(file_url)

        raise(InvalidTarballUrl, "Invalid tarball URL: #{file_url}") unless file_url_match

        File.join("repository_files", file_url_match["id"], file_url_match["basename"])
      end
    end
  end
end
