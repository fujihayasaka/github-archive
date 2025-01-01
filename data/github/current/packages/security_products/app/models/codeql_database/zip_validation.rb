# typed: true
# frozen_string_literal: true

require "azure/core/http/http_error"

module CodeqlDatabase::ZipValidation
  extend T::Helpers
  include CodeScanningQueriesHelper

  requires_ancestor { CodeqlDatabase }

  GENERIC_ERROR_MESSAGE = "Upload does not appear to be a valid CodeQL database"

  # Validates that the data that was uploaded appears to be a valid
  # CodeQL database for the correct language.
  # This reads the database contents from storage.
  # Returns an error message, or nil if everything is ok.
  def validate_database_contents
    # Read the first 1KB of the input stream. This should hopefully be all we
    # need to validate if the upload is a valid CodeQL database or not.
    begin
      blob, content = CodeScanningQueriesHelper.azure_client.get_blob(
        GitHub.codeql_variant_analysis_azure_container,
        storage_s3_key(nil),
        start_range: 0,
        end_range: 1024,
      )
    rescue ::Azure::Core::Http::HTTPError => error
      Failbot.report(
        error,
        "gh.code_scanning.codeql_database_storage_s3_key": storage_s3_key(nil),
        "gh.repo.id": repository&.id,
      )
      return "Could not read database contents"
    end

    # Check that the first 4 bytes match the expected start of a zip file.
    if content[0..3] != [80, 75, 3, 4].pack("C*") # pack("C*") means unsigned 8 bit integers
      GitHub.logger.warn(
        "Uploaded CodeQL database does not appear to be a zip file",
        "code.namespace" => self.class.name,
        "code.function" => __method__.to_s,
        "gh.repo.id" => repository&.id,
        "gh.code_scanning_multi_repository_variant_analysis.codeql_database.storage_s3_key" => storage_s3_key(nil),
      )
      return GENERIC_ERROR_MESSAGE
    end

    # Search for the name of the codeql-database.yml file. This is possible
    # because the paths of files in a ZIP are in plaintext and not compressed,
    # and due to the names of files present in a CodeQL database the
    # codeql-database.yml will always appear near the start of the ZIP.
    # We don't currently look at the contents of the file, but just
    # checking that this string exists should be good enough for now
    # until we can implement reading the ZIP file contents properly.
    if !content.include?("codeql-database.yml")
      GitHub.logger.warn(
        "Uploaded CodeQL database does not contain codeql-database.yml",
        "code.namespace" => self.class.name,
        "code.function" => __method__.to_s,
        "gh.repo.id" => repository&.id,
        "gh.code_scanning_multi_repository_variant_analysis.codeql_database.storage_s3_key" => storage_s3_key(nil),
      )
      return GENERIC_ERROR_MESSAGE
    end

    # Database appears to be valid,
    # or at least this is as much as we're currently checking
    nil
  end
end
