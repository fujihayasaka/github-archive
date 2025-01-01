# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class LegacyMigration < Platform::Objects::Base
      description "A migration tracks the import and export of a repository."

      # That max amount of conflicts to generate in conflicts query
      MAX_CONFLICTS = 500.freeze

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, migration)
        Loaders::ActiveRecord.load(::Organization, migration.owner_id).then do |owner|
          permission.access_allowed?(:migration_import, resource: owner, organization: owner, current_repo: nil, allow_integrations: false, allow_user_via_granular_actor: false)
        end
      end

      implements_node templates: [
        [:um, :user_id, :id],
        [:om, :org_id, :id],
      ], as: "LM", ready_date: Platform::Helpers::GlobalId::COHORT_2 do |legacy_migration|
        legacy_migration.async_owner.then do |owner|
          case owner.type
          when "User"
            { prefix: :um, user_id: owner.id, id: legacy_migration.id }
          when "Organization"
            { prefix: :om, org_id: owner.id, id: legacy_migration.id }
          else
            raise Platform::Errors::Internal, "Unexpected legacy migration owner: #{owner.inspect} (#{owner.class})"
          end
        end
      end

      def self.load_from_next_global_id(parsed_id)
        load_from_global_id(parsed_id.id)
      end

      def self.load_from_global_id(id)
        Platform::Objects.async_find_record_by_id(::Migration, id)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        object.async_owner.then do |owner|
          owner.adminable_by?(permission.viewer)
        end
      end

      feature_flag :gh_migrator_import_to_dotcom

      minimum_accepted_scopes ["admin:org"]

      database_id_field

      field :state, Enums::ImportExportState, "The migration's state", null: true
      field :guid, String, "The migration's UUID.", null: false
      field :upload_url, Platform::Scalars::URI, description: "The URL where one may upload an import archive.", null: false

      field :upload_url_template, String, description: "The template URL where one may upload an import archive.", null: false do
        deprecated(
          start_date: Date.new(2018, 11, 13),
          reason: "`uploadUrlTemplate` is being removed because it is not a standard URL and adds an extra user step.",
          superseded_by: "Use `uploadUrl` instead.",
          owner: "tambling",
        )
      end

      field :source_product, String, description: "The source product that the archive was created from.", null: false, feature_flag: :gh_migrator_import_to_dotcom

      def upload_url
        migration_path = "/migrations/#{@object.id}/archive"

        uri = URI.parse(GitHub.api_upload_prefix)
        uri.path = File.join(uri.path, migration_path)
        uri.query = { name: "migration_upload.tar.gz" }.to_query

        uri
      end

      def upload_url_template
        "#{GitHub.api_upload_prefix}/migrations/#{@object.id}/archive{?name}"
      end

      field :migratable_resources, Connections::MigratableResource, description: "Get a list of migratable resource mappings to audit a migration.", null: true, connection: true do
        argument :model_name, String, "Filter migratable resources by their model name.", required: false
        argument :source_url, Scalars::URI, "Filter migratable resources by their source URL.", required: false
        argument :target_url, Scalars::URI, "Filter migratable resources by their target URL.", required: false
        argument :state, Enums::MigratableResourceState, "Filter migratable resources by their state.", required: false
        argument :only_with_warning, Boolean, "Filter migratable resources by whether or not they have a warning.", required: false, default_value: false
      end

      def migratable_resources(**arguments)
        where = { guid: @object.guid }
        if arguments.key?(:state)
          where[:state] = Array.wrap(arguments[:state]).map do |state|
            ::MigratableResource.states[state]
          end
        end

        ([:model_name, :source_url, :target_url] & arguments.keys).each do |key|
          field_name = key.to_s.camelize(:lower)
          field_on_migratable_resource = MigratableResource.fields.fetch(field_name)
          # `method_sym` is the overridden method or the default one
          where_param = field_on_migratable_resource.method_sym
          where[where_param] = arguments[key]&.to_s
        end

        ::MigratableResource.where(where).tap do |scope|
          if arguments[:only_with_warning]
            scope.merge!(::MigratableResource.where.not(warning: nil))
          end
        end
      end

      field :conflicts, [Objects::MigrationMapConflict], description: "A migration import mapping conflict", null: true

      def conflicts
        ActiveRecord::Base.connected_to(role: :reading) do
          object.async_owner.then do |organization|
            organization.async_business.then do
              GitHub.cache.fetch("import_migration_conflicts", @object.updated_at) do
                uncached_conflicts = []
                GitHub.migrator.conflicts(@object, max_conflicts: MAX_CONFLICTS) do |model_type, source_url, target_url, recommended_action, notes|
                  uncached_conflicts.push(
                    Platform::Models::MigrationMapConflict.new(
                      model_type,
                      source_url,
                      target_url,
                      recommended_action,
                      notes,
                    ),
                  )
                end
                uncached_conflicts
              end
            end
          end
        end
      end
    end
  end
end
