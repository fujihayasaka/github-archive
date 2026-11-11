# typed: true
# frozen_string_literal: true

module Api::Serializer::OctoshiftMigrationArchivesDependency
  extend T::Helpers

  requires_ancestor { Api::Serializer }

  # Creates a Hash to be serialized to JSON.
  def octoshift_migration_archive_hash(octoshift_migration_archive, options = {})
    options = Api::SerializerOptions.from(options)

    {
      guid: octoshift_migration_archive.guid,
      node_id: global_id_for(octoshift_migration_archive, options),
      name: octoshift_migration_archive.name,
      size: octoshift_migration_archive.size,
      uri: octoshift_migration_archive.gei_uri,
      created_at: octoshift_migration_archive.created_at
    }
  end
end
