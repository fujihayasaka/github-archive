# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class AddImportMapping < Platform::Mutations::Base
      include Helpers::LegacyMigration

      description "Add the import mapping for a GitHub migration import."

      feature_flag :gh_migrator_import_to_dotcom
      minimum_accepted_scopes ["admin:org"]

      argument :migration_id, ID, "The ID of a migration to add migration import mapping.", required: true, loads: Objects::LegacyMigration
      argument :mappings, [Inputs::MigrationImportMapping, null: true], "The import mappings being processed.", required: true

      field :migration, Objects::LegacyMigration, "The target import migration to add mappings to.", null: true

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

        # create mappings array
        mappings = inputs[:mappings].map do |import_mapping|
          {
            "model_name" => import_mapping[:model_name],
            "source_url" => import_mapping[:source_url].strip,
            "target_url" => import_mapping[:target_url].strip,
            # We cast this as a string so ActiveJob can serialize it
            "action"     => import_mapping[:action].to_s,
          }
        end

        GitHub.migrator.map_later(migration, mappings, context[:viewer])

        {
          migration: migration.reload,
        }
      end
    end
  end
end
