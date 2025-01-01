# typed: strict
# frozen_string_literal: true

module SecretScanning::Util
  class RawSecret
    extend T::Sig

    # Text to display if raw secret is not found
    ARCHIVE_FILE_RAW_SECRET = "NOT_FOUND: Unavailable for archive files"
    FILE_TOO_LARGE = "NOT_FOUND: File too large"
    BLOB_NOT_FOUND = "NOT_FOUND: No longer present in git history"
    NOT_FOUND_MESSAGES = T.let([
      ARCHIVE_FILE_RAW_SECRET,
      FILE_TOO_LARGE,
      BLOB_NOT_FOUND
    ], T::Array[String])
    NO_PREVIEW_MESSAGE = "No preview"

    sig { params(alert: T.any(GitHub::TokenScanning::Service::Token, TokenScanResult)).void }
    def self.replacement_for_nil_raw_secret(alert)
      alert.raw_secret = SecretScanning::Util::RawSecret::NO_PREVIEW_MESSAGE

      if alert.found_in_archive?
        alert.raw_secret = SecretScanning::Util::RawSecret::ARCHIVE_FILE_RAW_SECRET
      end
    end

    sig { params(secret: T.nilable(String)).returns(T.nilable(String)) }
    def self.token_literal_from_secret(secret)
      case secret
      when BLOB_NOT_FOUND, ARCHIVE_FILE_RAW_SECRET, FILE_TOO_LARGE, nil
        nil
      else
        encoded_secret(secret)
      end
    end

    # Encodes raw secrets to handle non UTF-8 characters
    sig { params(secret: String).returns(String) }
    def self.encoded_secret(secret)
      encoded_secret = secret.dup.force_encoding("UTF-8")
      if encoded_secret.valid_encoding?
        encoded_secret
      else
        NO_PREVIEW_MESSAGE
      end
    end

    sig do params(
      alert: T.any(GitHub::TokenScanning::Service::Token, TokenScanResult),
      repository: Repository,
      location_blobs: T.untyped,
      multiline_secret_with_newline: T::Boolean,
    ).void
    end
    def self.set_raw_secret(alert, repository, location_blobs, multiline_secret_with_newline: false)
      return if alert.raw_secret.present?
      alert.raw_secret = get_raw_secret_from_first_location(alert, repository, location_blobs, multiline_secret_with_newline: multiline_secret_with_newline)
      if alert.raw_secret.nil?
        Failbot.report(SecretScanning::Errors::Error.new("Unable to fetch raw secret"), repo_id: repository.id, alert_number: alert.number, secret_type: alert.token_type)
      end
    end

    # Extracts raw secret literal when provided with an alert.
    sig do
      params(
        alert: T.nilable(T.any(GitHub::TokenScanning::Service::Token, TokenScanResult)),
        repository: Repository,
        location_blobs: T.untyped,
        multiline_secret_with_newline: T::Boolean,
      ).returns(T.nilable(String))
    end
    def self.get_raw_secret_from_first_location(alert, repository, location_blobs, multiline_secret_with_newline: false)
      get_raw_secret_from_location(alert&.first_location, repository, location_blobs, alert, multiline_secret_with_newline: multiline_secret_with_newline)
    end

    # Note that the dogstat logs mention "api" in the name.
    # This isn't an "api" space, but those names are left here
    # in case some dashboard reads those stats.
    sig do
      params(
        location: T.untyped,
        repository: Repository,
        location_blobs: T.untyped,
        alert: T.nilable(T.any(GitHub::TokenScanning::Service::Token, TokenScanResult)),
        custom_pattern_id: T.nilable(Integer),
        is_dry_run: T::Boolean,
        multiline_secret_with_newline: T::Boolean,
      ).returns(T.nilable(String))
    end
    def self.get_raw_secret_from_location(
      location,
      repository,
      location_blobs,
      alert = nil,
      custom_pattern_id = nil,
      is_dry_run = false,
      multiline_secret_with_newline: false
    )
      alert_number = alert&.number || nil
      secret_type = nil

      unless alert.nil?
        secret_type = alert.token_type
      end

      unless custom_pattern_id.nil?
        secret_type = "cp_#{custom_pattern_id}"
      end

      if location.nil?
        unless !alert.nil? && alert.resolution == GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::HIDDEN_BY_CONFIG
          Failbot.report(
            SecretScanning::Errors::Error.new("Unable to retrieve location for secret"),
            repo_id: repository.id,
            alert_number: alert_number,
            secret_type: secret_type,
            is_dry_run: is_dry_run
          )
        end
        return NO_PREVIEW_MESSAGE
      end

      blob = location_blobs[location.blob_oid]

      if location.start_line.zero? && location.end_line.zero?
        GitHub.dogstats.increment("secret_scanning.raw_secret_preview", tags: ["success:false", "dry_run:#{is_dry_run}", "error:archive_file_raw_secret"])
        return ARCHIVE_FILE_RAW_SECRET
      end

      if blob.nil?
        GitHub.dogstats.increment("secret_scanning.raw_secret_preview", tags: ["success:false", "dry_run:#{is_dry_run}", "error:blob_not_found"])
        return BLOB_NOT_FOUND
      end

      start_column = location.start_column
      end_column = location.end_column
      true_start_line = location.start_line - 1
      true_end_line = location.end_line - 1

      if blob.fetch("binary", false)
        GitHub.logger.info(
          "code.function" => "get_raw_secret_from_location",
          "exception.message" => "failed to extract secret for binary file",
          "gh.repo.id" => repository.id,
          "gh.repo.owner.id" => repository.owner&.id,
          "gh.secret_scanning.alert.number" => alert_number,
          "gh.secret_scanning.alert.secret_type" => secret_type,
          "gh.secret_scanning.alert.blob.oid" => location.blob_oid,
          "gh.secret_scanning.alert.is_dry_run" => is_dry_run,
        )
        GitHub.dogstats.increment("secret_scanning.raw_secret_preview", tags: ["success:false", "dry_run:#{is_dry_run}", "error:binary_file"])
        return NO_PREVIEW_MESSAGE
      end

      if blob.fetch("encoding", "").downcase != "utf-8"
        GitHub.logger.info(
          "code.function" => "get_raw_secret_from_location",
          "exception.message" => "failed to extract secret for non-utf-8 file",
          "gh.repo.id" => repository.id,
          "gh.repo.owner.id" => repository.owner&.id,
          "gh.secret_scanning.alert.number" => alert_number,
          "gh.secret_scanning.alert.secret_type" => secret_type,
          "gh.secret_scanning.alert.blob.oid" => location.blob_oid,
          "gh.secret_scanning.alert.is_dry_run" => is_dry_run,
        )
        GitHub.dogstats.increment("secret_scanning.raw_secret_preview", tags: ["success:false", "dry_run:#{is_dry_run}" , "error:non_utf8_encoding", "encoding:#{blob.fetch("encoding", "")}"])
        return NO_PREVIEW_MESSAGE
      end

      # Retrieve data value for blob
      blob_content = T.cast(blob["data"], String).encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
      if blob_content.nil?
        GitHub.dogstats.increment("secret_scanning.raw_secret_preview", tags: ["success:false", "dry_run:#{is_dry_run}", "error:blob_content_not_found"])
        return BLOB_NOT_FOUND
      end

      blob_content_lines = blob_content.split("\n", -1)

      # Extract relevant lines and stringify
      secret_line_content_slice = blob_content_lines[true_start_line..true_end_line]
      if secret_line_content_slice.nil?
        if blob["truncated"]
          GitHub.dogstats.increment("secret_scanning.raw_secret_preview", tags: ["success:false", "dry_run:#{is_dry_run}", "error:truncated_blob_lines_not_found"])
          return FILE_TOO_LARGE
        else
          Failbot.report(
            SecretScanning::Errors::Error.new("Unable to retrieve relevant lines for secret from blob"),
            repo_id: repository.id,
            alert_number: alert_number,
            secret_type: secret_type,
            is_dry_run: is_dry_run
          )
          return nil
        end
      end

      secret_line_content = if multiline_secret_with_newline
        secret_line_content_slice.join("\n")
      else
        secret_line_content_slice.join
      end

      if true_start_line == true_end_line
        # When token occurs in the same line, just extract using start and end columns
        raw_token = secret_line_content.bytes[start_column...end_column]
      else
        # When tokens across different lines, calculate length of last line
        # Then use it to find offset to extract from the end of the string
        last_line = blob_content_lines[true_end_line]
        if last_line.nil?
          Failbot.report(
            SecretScanning::Errors::Error.new("Unable to retrieve last line for secret from blob"),
            repo_id: repository.id,
            alert_number: alert_number,
            secret_type: secret_type,
            is_dry_run: is_dry_run
          )
          return nil
        end

        end_column_offset = last_line.length - end_column
        raw_token =
        if end_column_offset == 0
          secret_line_content.bytes[start_column..]
        else
          secret_line_content.bytes[start_column...-end_column_offset]
        end
      end

      if raw_token.nil?
        if blob["truncated"]
          GitHub.dogstats.increment("secret_scanning.raw_secret_preview", tags: ["success:false", "dry_run:#{is_dry_run}", "error:truncated_blob_columns_not_found"])
          return FILE_TOO_LARGE
        else
          Failbot.report(
            SecretScanning::Errors::Error.new("Error extracting token from blob content. column and line values were insufficient to get the token"),
            repo_id: repository.id,
            alert_number: alert_number,
            secret_type: secret_type,
            start_column: location.start_column,
            end_column: location.end_column,
            start_line: location.start_line,
            end_line: location.end_line,
            blob_lines: blob_content_lines.length,
            blob_length: blob_content.length,
            is_dry_run: is_dry_run
          )

          GitHub.dogstats.increment("secret_scanning.raw_secret_preview", tags: ["success:false", "dry_run:#{is_dry_run}", "error:could_not_extract_token_by_line_and_column"])
          return NO_PREVIEW_MESSAGE
        end
      end

      if !is_dry_run
        GitHub.logger.info(
          "code.function" => "get_raw_secret_from_location",
          "exception.message" => "looked up a raw secret",
          "gh.repo.id" => repository.id,
          "gh.repo.owner.id" => repository.owner&.id,
          "gh.secret_scanning.alert.number" => alert_number,
          "gh.secret_scanning.alert.secret_type" => secret_type,
          "gh.secret_scanning.alert.blob.oid" => location.blob_oid,
          "gh.secret_scanning.alert.is_dry_run" => is_dry_run,
        )
      end

      GitHub.dogstats.increment("secret_scanning.raw_secret_preview", tags: ["success:true", "dry_run:#{is_dry_run}"])
      raw_token.pack("c*")
    end
  end
end
