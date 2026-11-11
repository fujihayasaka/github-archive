# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UnlockImportedRepositories < Platform::Mutations::Base
      include Helpers::LegacyMigration

      description "Unlocks repositories tied to an import migration"

      feature_flag :gh_migrator_import_to_dotcom

      minimum_accepted_scopes ["admin:org"]

      argument :migration_id, ID, "The Node ID of the importing organization.", required: true, loads: Objects::LegacyMigration

      field :migration, Objects::LegacyMigration, "The import migration.", null: true
      field :unlocked_repositories, [Objects::Repository], "The repositories that were unlocked.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, migration:, **inputs)
        Loaders::ActiveRecord.load(::Organization, migration.owner_id).then do |org|
          permission.access_allowed?(:migration_import, resource: org, organization: org, current_repo: nil, allow_integrations: false, allow_user_via_granular_actor: false)
        end
      end

      def resolve(migration:, **inputs)
        unless feature_flag_enabled?(migration.owner)
          raise Errors::Forbidden.new("Organization #{migration.owner.display_login} is not authorized to perform imports.")
        end

        begin
          unlocked_repositories = GitHub.migrator.unlock!(migration)
        rescue GitHub::Migrator::CannotUnlockOnFailedImport,
               GitHub::Migrator::CannotUnlockImportAgain,
               GitHub::Migrator::CannotUnlockImportInProgress
          raise(
            Platform::Errors::Unprocessable,
            "Unlock of migration repositories can only be called once after a successful import.",
          )
        end

        { migration: migration, unlocked_repositories: unlocked_repositories }
      end
    end
  end
end
