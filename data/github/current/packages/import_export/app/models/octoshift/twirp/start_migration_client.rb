# typed: true
# frozen_string_literal: true

require "monolith-twirp-octoshift-migrations"

module Octoshift
  module Twirp
    class StartMigrationClient
      attr_reader :client

      # Public: Construct a CreateImportClient.
      #
      # faraday_connection - A Faraday::Connection instance.
      def initialize(faraday_connection: ConnectionBuilder.new.build)
        @client = MonolithTwirp::Octoshift::Migrations::V1::StartMigrationAPIClient.new(faraday_connection)
      end

      # Public: Starts a new migration.
      #
      # Raises an Octoshift::Twirp::Error if the request fails.
      #
      # user_id - The ID of the user that wants to create an import.
      # repository_name - The name the imported repository will have.
      # source_connector_id - The ID of the source connector.
      # source_identifier_url - Is the source identifier url.
      # continue_on_error - The flag which determines whether a migration will continue on error.
      # git_archive_url - The signed URL to access the user-uploaded git archive (optional).
      # metadata_archive_url - The signed URL to access the user-uploaded metadata archive (optional).
      # access_token - The Octoshift migration source access token (optional).
      # github_pat - The GitHub personal access token of the user importing to the target repository (optional).
      # skip_releases - The flag to skip migrating releases for a repository (optional).
      # target_repo_visibility - The visibility level for the imported repository (optional). Can be "private", "internal", or "public".
      #
      # Returns the migration object.
      def start_migration(user_id:, repository_name:, source_connector_id:, source_identifier_url:, continue_on_error:, skip_releases: false, git_archive_url: "", metadata_archive_url: "", access_token: "", github_pat: "", target_repo_visibility: "private", lock_source: false)
        target_repo_visibility = map_visibility_to_twirp_enum(target_repo_visibility)

        response = client.start_migration(
          user_id: user_id,
          repository_name: repository_name,
          source_connector_id: source_connector_id,
          source_identifier_url: source_identifier_url,
          continue_on_error: continue_on_error,
          git_archive_url: git_archive_url,
          metadata_archive_url: metadata_archive_url,
          access_token: access_token,
          github_pat: github_pat,
          skip_releases: skip_releases,
          target_repo_visibility: target_repo_visibility,
          should_lock_source: lock_source
        )

        raise Error, response.error if response.error

        response.data.migration
      end

      def map_visibility_to_twirp_enum(visibility)
        map = {
          "private" => :REPOSITORY_VISIBILITY_PRIVATE,
          "public" => :REPOSITORY_VISIBILITY_PUBLIC,
          "internal" => :REPOSITORY_VISIBILITY_INTERNAL
        }

        map[visibility]
      end
    end
  end
end
