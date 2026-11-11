# typed: true
# frozen_string_literal: true

# Implements the API that Alambic uses for serving or accepting migration archive
# uploads through the Alambic storage cluster. Used in local development.
#
# https://github.com/github/alambic/tree/master/docs/assets
class Api::Internal::StorageMigrationArchives < Api::Internal::StorageUploadable
  require_api_semantic_version "smasher"

  def self.enforce_private_mode?
    false
  end

  get "/internal/storage/migrations/:id/archive/:guid", operation_id: :internal do
    @route_owner = "@github/data-liberation"
    migration = get_migration(params[:id])
    control_access :write_migration, resource: migration.owner, allow_integrations: false, allow_user_via_granular_actor: false

    migration_file = migration.file
    deliver :internal_storage_hash, migration_file, env: request.env
  end

  post "/internal/storage/migrations/:id/archive", operation_id: :internal do
    @route_owner = "@github/data-liberation"
    migration = get_migration(params[:id])
    control_access :write_migration, resource: migration.owner, allow_integrations: false, allow_user_via_granular_actor: false
    validate_uploadable MigrationFile,
      meta: { migration_id: migration.id }
  end

  post "/internal/storage/migrations/:id/archive/verify", operation_id: :internal do
    @route_owner = "@github/data-liberation"
    migration = get_migration(params[:id])
    response = create_uploadable MigrationFile,
      meta: { migration_id: migration.id }
    migration.upload_archive!
    response
  end

  def verify_user(meta)
    MigrationFile.storage_verify_token(@asset_token, meta)
  end

  private

  def get_migration(migration_id)
    migration = ActiveRecord::Base.connected_to(role: :reading) { Migration.find_by(id: migration_id) }
    migration || deliver_error!(404, message: "cannot find migration with id \`#{migration_id}\`")
  end
end
