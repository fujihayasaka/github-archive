# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Services
    # Shared service for serializing token location data (blob, commit, git metadata)
    # into hashes suitable for the React layer.
    #
    # Used by both ShowPayloadBuilder (alert show page) and PublicMonitoringController
    # (enterprise public monitoring detail panel).
    class LocationSerializationService
      BLOB_PADDING = 5

      sig { params(location: GitHub::TokenScanning::Service::TokenLocation).returns(T::Hash[Symbol, T.untyped]) }
      def self.serialize_git_location(location)
        {
          path: location.path,
          start_line: location.start_line,
          end_line: location.end_line,
          start_column: location.start_column,
          end_column: location.end_column,
          found_in_archive: location.found_in_archive?,
          commit: {
            oid: location.commit_oid,
          },
        }
      end

      sig { params(commit: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
      def self.serialize_commit(commit)
        return {} if commit.nil?

        {
          message: commit_message(commit),
          author: {
            avatar_url: commit.author&.primary_avatar_url,
          },
          created_at: commit.created_at,
        }
      end

      # Returns sanitized HTML commit message when available (repo commits),
      # or HTML-escaped plain text for wiki commits whose repository
      # (GitHub::Unsullied::Wiki) does not support short_message_html.
      sig { params(commit: T.untyped).returns(String) }
      def self.commit_message(commit)
        commit.short_message_html
      rescue NoMethodError
        ERB::Util.html_escape(commit.short_message_text)
      end

      sig { params(location: GitHub::TokenScanning::Service::TokenLocation).returns(T::Boolean) }
      def self.blob_available?(location)
        return false if location.found_in_archive?
        return false if location.blob.nil?

        true
      end

      sig { params(location: GitHub::TokenScanning::Service::TokenLocation).returns(T::Hash[Symbol, T.untyped]) }
      def self.serialize_blob(location)
        return {} if location.blob.nil?

        blob = location.blob
        {
          oid: location.blob_oid,
          lines: code_snippet_lines(location),
          is_truncated: blob&.truncated?,
          is_text: blob&.text?,
          language: blob&.language ? blob.language.name.parameterize : "text",
        }
      end

      # Returns colorized HTML lines for the code snippet surrounding the secret,
      # with BLOB_PADDING lines of context on each side.
      sig { params(location: GitHub::TokenScanning::Service::TokenLocation).returns(T::Array[String]) }
      def self.code_snippet_lines(location)
        blob = location.blob
        return [] if blob.nil?

        return [] if blob.truncated?
        return [] if blob.binary?

        begin
          colorized_lines = blob.colorized_lines || []
        rescue => e
          # gracefully fail and report errors if getting code lines fails for any reason,
          # as it is not critical to the experience and may fail for reasons outside of our control
          Failbot.report(e, blob_oid: location.blob_oid, repository_id: location.repository.id)
          GitHub.logger.error(
            "failed to get colorized lines for secret scanning location",
            exception: e,
            "gh.blob.oid": location.blob_oid,
            "gh.secret_scanning.repo.id": location.repository.id,
          )
          return []
        end

        blob_slice_start = [location.start_line - BLOB_PADDING - 1, 0].max
        blob_slice_end = [location.end_line + BLOB_PADDING - 1, colorized_lines.length].min

        colorized_lines[blob_slice_start..blob_slice_end] || []
      end

      # Serializes a single location with commit and blob data into a camelCase hash
      # suitable for JSON API responses consumed by React slide-out panels (pubmon, ACV).
      #
      # Unlike ShowPayloadBuilder#serialize_location (which returns snake_case for the
      # full show page payload and handles all content types), this method returns a
      # flat camelCase hash for all location content types.
      sig do
        params(
          location: GitHub::TokenScanning::Service::TokenLocation,
          repository: Repository,
        ).returns(T::Hash[Symbol, T.untyped])
      end
      def self.serialize_location_for_ui(location, repository)
        loc = {
          path: location.path,
          commitOid: location.commit_oid,
          startLine: location.start_line,
          endLine: location.end_line,
          startColumn: location.start_column,
          endColumn: location.end_column,
          contentType: location.content_type.to_s,
          contentNumber: location.content_number,
          contentId: location.content_id,
          createdAt: location.created_at,
          foundInArchive: location.found_in_archive?,
        }

        # Only look up commit data for blob-type locations. Non-blob content
        # types (issues, PRs, discussions, etc.) don't have a meaningful git
        # commit OID, and attempting the lookup can raise on blank/invalid OIDs.
        # Wiki commits live in the wiki's git repo, not the main repo.
        content_type = location.content_type.to_s
        commit = if content_type == "WIKI_BLOB"
          repository.find_wiki_commit(location.commit_oid)
        elsif content_type == "REPOSITORY_BLOB"
          repository.find_commit(location.commit_oid)
        end
        if commit
          commit_data = serialize_commit(commit)
          loc[:commitMessage] = commit_data[:message]
          loc[:commitCreatedAt] = commit_data[:created_at]
          loc[:commitAuthorAvatarUrl] = commit_data.dig(:author, :avatar_url)
          loc[:commitAuthorEmail] = commit.author_email
        end

        if blob_available?(location)
          blob_data = serialize_blob(location)
          loc[:blob] = {
            lines: blob_data[:lines],
            language: blob_data[:language],
            isTruncated: blob_data[:is_truncated],
            isText: blob_data[:is_text],
          }
        end

        loc
      end
    end
  end
end
