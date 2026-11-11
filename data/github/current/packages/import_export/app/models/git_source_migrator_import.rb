# typed: true
# frozen_string_literal: true

class GitSourceMigratorImport
  # Create a new GitSourceMigratorImport instance.
  #
  # @param [User] user User performing the migration.
  # @param [Repository] repository Target repository for the migration.
  # @return [void]
  def initialize(user:, repository:, client_source_type:)
    @user = user
    @repository = repository
    @client_source_type = client_source_type
  end

  attr_reader :user, :repository, :client_source_type

  # Start a new migration.
  #
  # @param [String] source_url Source URL of the VCS to migrate from.
  # @param [:SOURCE_TYPE_GITHUB, :SOURCE_TYPE_AZURE_DEVOPS, :SOURCE_TYPE_BITBUCKET_SERVER,
  #   :SOURCE_TYPE_SOURCE_IMPORT] source_type Source type of the VCS to migrate from.
  # @param [String, nil] source_username Source username if needed, or nil if not needed.
  # @param [String, nil] source_access_token Source password (or PAT) if needed, or nil if not needed.
  # @param [String, nil] git_archive_url URL for downloading archive of Git data if needed, or nil if not needed.
  # @param [:ARCHIVE_FORMAT_GITHUB, :ARCHIVE_FORMAT_BITBUCKET_SERVER] archive_format Type of archive to process if needed, or nil if not needed.
  # @param [String, nil] target_wiki_ssh_url SSH Git URL for the target wiki repository if needed, or nil if not needed.
  # @raise [GitSrcMigrator::Twirp::Error] Error returned when attempting to query information about a migration.
  # @return [Integer] The migration ID of the new migration.
  def start_import(source_url:, source_type:, source_username: nil, source_access_token: nil, git_archive_url: nil, archive_format: nil, target_wiki_ssh_url: nil)
    migration_client.start_migration(
      source_url: source_url,
      source_type: source_type,
      source_access_token: source_access_token,
      repository_id: repository.id,
      target_owner_id: repository.owner.id,
      target_ssh_url: repository.ssh_url,
      source_username: source_username,
      user_id: user.id,
      client_source_type: client_source_type,
      git_archive_url: git_archive_url,
      archive_format: archive_format,
      target_wiki_ssh_url: target_wiki_ssh_url
    )
  end

  # Get information about an existing migration.
  #
  # @raise [GitSrcMigrator::Twirp::Error] Error returned when attempting to query information about a migration.
  # @return [MonolithTwirp::GitSrcMigrator::Migrations::V1::Migration] Information about a migration.
  def status
    migration_client.get_migration(repository_id: repository.id)
  end

  # Check if a migration exists in GSM.
  #
  # @return [true] A migration exists in GSM for the target repository.
  # @return [false] A migration does not exist in GSM for the target repository.
  def migration_exists?
    true if status
  rescue GitSrcMigrator::Twirp::Error
    false
  end

  private

  def migration_client
    @migration_client ||= begin
      connection = GitSrcMigrator::Twirp::ConnectionBuilder.for_owner(repository.owner).build
      GitSrcMigrator::Twirp::MigrationClient.new(faraday_connection: connection)
    end
  end
end
