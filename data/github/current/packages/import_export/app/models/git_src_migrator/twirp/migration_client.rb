# typed: true
# frozen_string_literal: true

require "monolith-twirp-git_src_migrator-migrations"

module GitSrcMigrator
  module Twirp
    class MigrationClient
      attr_reader :client

      # Construct a MigrationClient.
      #
      # @param [Faraday::Connection] faraday_connection A configured Connection object to make Twirp requests.
      # @return [void]
      def initialize(faraday_connection: ConnectionBuilder.new.build)
        @client = MonolithTwirp::GitSrcMigrator::Migrations::V1::MigrationAPIClient.new(faraday_connection)
      end

      # Get information about an existing migration.
      #
      # @param [Integer, nil] id GSM migration ID of a migration to query information for.
      # @param [Integer, nil] repository_id GitHub repository ID of a migration to query information for.
      # @raise [Error] Error returned when attempting to query information about a migration.
      # @return [MonolithTwirp::GitSrcMigrator::Migrations::V1::Migration] Information about a migration.
      def get_migration(id: nil, repository_id: nil)
        response = client.get_migration(
          id: id,
          repository_id: repository_id
        )

        raise Error, response.error if response.error

        response.data.migration
      end

      # Start a new migration.
      #
      # @param [String] source_url Source URL of the VCS to migrate from.
      # @param [:SOURCE_TYPE_GITHUB, :SOURCE_TYPE_AZURE_DEVOPS, :SOURCE_TYPE_BITBUCKET_SERVER,
      #   :SOURCE_TYPE_SOURCE_IMPORT, :SOURCE_TYPE_GITLAB] source_type Source VCS type.
      # @param [String, nil] source_access_token Access token to authenticate to the source VCS if needed, or nil if
      #   not needed.
      # @param [String, nil] git_archive_url URL for downloading archive of Git data if needed, or nil if not needed.
      # @param [Integer] repository_id Target repository database ID.
      # @param [Integer] target_owner_id User database ID of the target repository owner.
      # @param [String] target_ssh_url SSH Git URL for the target repository.
      # @param [String, nil] target_wiki_ssh_url SSH Git URL for the target wiki repository if needed, or nil if not
      # @param [String, nil] source_username Username for authenticating to a VCS source if needed, or nil if not
      #   needed.
      # @param [Array<String>] tags Tags to identify the migration.
      # @param [Integer] user_id GitHub user ID of the user who initiated the migration.
      # @param [:ARCHIVE_FORMAT_GITHUB, :ARCHIVE_FORMAT_BITBUCKET_SERVER]
      #   archive_format Type of archive to process if needed.
      # @param [:CLIENT_SOURCE_TYPE_OCTOSHIFT, :CLIENT_SOURCE_TYPE_SOURCE_IMPORT, :CLIENT_SOURCE_TYPE_ECI]
      #   client_source_type Type of client source initiating the migration.
      # @raise [Error] Error returned when attempting to start a migration.
      # @return [Integer] The migration ID of the new migration.
      def start_migration(
        source_url:,
        source_type:,
        source_access_token: nil,
        git_archive_url: nil,
        repository_id:,
        target_owner_id:,
        target_ssh_url:,
        target_wiki_ssh_url: nil,
        source_username: nil,
        tags: [],
        user_id:,
        archive_format: nil,
        client_source_type: nil
      )
        response = client.start_migration(
          source_url: source_url,
          source_type: source_type,
          source_access_token: source_access_token,
          git_archive_url: git_archive_url,
          repository_id: repository_id,
          target_owner_id: target_owner_id,
          target_ssh_url: target_ssh_url,
          target_wiki_ssh_url: target_wiki_ssh_url,
          source_username: source_username,
          tags: tags,
          user_id: user_id,
          archive_format: archive_format,
          client_source_type: client_source_type
        )

        raise Error, response.error if response.error

        response.data.migration.id
      end
    end
  end
end
