# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class MigrationMapConflict < Platform::Objects::Base
      description "A migration import mapping conflict"

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      # MigrationMapConflicts are not tied to any active record models,
      # we want to intentionally skip the `access_allowed?` logic here
      # and just return true.
      def self.async_api_can_access?(permission, conflict)
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      feature_flag :gh_migrator_import_to_dotcom

      minimum_accepted_scopes ["admin:org"]

      field :model_name, String, "The model in a migration import mapping.", method: :model_type, null: false
      field :source_url, Scalars::URI, "The resource URL to migrate data from in a migration import mapping.", null: false
      field :target_url, Scalars::URI, "The resource URL to migrate data to in a migration import mapping.", null: true
      field :recommended_action, Enums::ImportMapAction, "The recommended map action that should resolve the map conflict for the migration import.", null: false
      field :notes, String, "Extra information reported about the migration conflict.", null: false
    end
  end
end
