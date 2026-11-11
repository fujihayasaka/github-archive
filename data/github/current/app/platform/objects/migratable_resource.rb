# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class MigratableResource < Platform::Objects::Base
      description "A migratable resource tracks migrations for individual items."

      implements_node templates: [[:mr, :id]], as: "MR", ready_date: Platform::Helpers::GlobalId::COHORT_1 do |migratable_resource|
        {
          prefix: :mr,
          id: migratable_resource.id
        }
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        Loaders::ActiveRecord.load(::Migration, object.guid, column: :guid).then do |migration|
          permission.typed_can_access?("LegacyMigration", migration)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        Loaders::ActiveRecord.load(::Migration, object.guid, column: :guid).then do |migration|
          permission.typed_can_see?("LegacyMigration", migration)
        end
      end

      feature_flag :gh_migrator_import_to_dotcom

      minimum_accepted_scopes ["admin:org"]

      field :model_name, String, "The model name of the migratable resource.", method: :model_type, null: false
      field :source_url, Scalars::URI, "The source URL for the migratable resource.", null: false
      field :target_url, Scalars::URI, "The target URL for the migratable resource.", null: true
      field :state, Enums::MigratableResourceState, "The migratable resource state.", null: true
      field :warning, String, "Any warning that may have been generated during mapping.", null: true
    end
  end
end
