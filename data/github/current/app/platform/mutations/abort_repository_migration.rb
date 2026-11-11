# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class AbortRepositoryMigration < Platform::Mutations::Base
      description "Abort a repository migration queued or in progress."

      minimum_accepted_scopes ["admin:org", "read:org", "repo"]

      argument :migration_id, ID, "The ID of the migration to be aborted.", required: true, loads: Objects::RepositoryMigration

      field :success, Boolean, "Did the operation succeed?", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, **inputs)
        permission.access_allowed?(
          :octoshift_import,
          resource: permission.viewer,
          current_repo: nil,
          current_org: nil
        )
      end

      def resolve(migration:, **inputs)
        user = context[:viewer]

        migration_client = ::Octoshift::Twirp::MigrationClient.new

        begin
          migration_client.abort_migration(
            migration_id: migration.id
          )
        rescue Octoshift::Twirp::Error => e
          raise Errors::InternalExecution.new(e.message)
        end

        { success: true }
      end
    end
  end
end
