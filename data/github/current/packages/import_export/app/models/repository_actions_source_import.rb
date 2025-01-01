# typed: true
# frozen_string_literal: true

class RepositoryActionsSourceImport
  # Create a new RepositoryActionsSourceImport instance.
  #
  # @param [User] user User performing the migration.
  # @param [Repository] repository Target repository for the migration.
  # @return [void]
  def initialize(user:, repository:)
    @user = user
    @repository = repository
  end

  attr_reader :user, :repository

  # Start a new migration.
  #
  # @param [String] source_url Source URL of the VCS to migrate from.
  # @param [String, nil] source_username Source username if needed, or nil if not needed.
  # @param [String, nil] source_access_token Source password (or PAT) if needed, or nil if not needed.
  # @raise [GitSrcMigrator::Twirp::Error] Error returned when attempting to query information about a migration.
  # @return [Integer] The migration ID of the new migration.
  def start_import(source_url:, source_username: nil, source_access_token: nil)
    migration_client.start_migration(
      source_url: source_url,
      source_type: :SOURCE_TYPE_SOURCE_IMPORT,
      source_access_token: source_access_token,
      repository_id: repository.id,
      target_owner_id: repository.owner.id,
      target_ssh_url: repository.ssh_url,
      source_username: source_username,
      user_id: user.id
    )
  end

  # Get information about an existing migration.
  #
  # @raise [GitSrcMigrator::Twirp::Error] Error returned when attempting to query information about a migration.
  # @return [MonolithTwirp::GitSrcMigrator::Migrations::V1::Migration] Information about a migration.
  def status
    @status ||= migration_client.get_migration(repository_id: repository.id)
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
