# typed: true
# frozen_string_literal: true

# This class is a service object that prepares a target schema for an import of a previously
# exported archive, by creating a MigratableResource in the target schema for each serialized
# model in the archive. This allows us to identify potential conflicts and request resolution
# from the end user.
module GitHub
  class Migrator
    class ImportPreparer
      include GitHub::Migrator::TarUtils
      include MigratorHelper

      BATCH_INSERT_SQL = <<~BATCH_INSERT_SQL
        INSERT IGNORE INTO
          #{MigratableResource.table_name}
          (guid,model_type,source_url,target_url,state,created_at,updated_at)
        :migratable_resources_values
      BATCH_INSERT_SQL

      # Public: Instantiates an ImportPreparer for the given repository and the migration
      # represented by guid.
      #
      # guid                  - A unique identifier representing the migration this model
      #                         will be prepared for.
      # archive_path:         - The location of the archive to extract
      # migration_path:       - The location to extract the serialized models to and read from.
      # events:               - An instance of GitHub::Migrator::Events that will notify its
      #                         subscribers of progress.
      def initialize(guid:, archive_path:, migration_path:, events: Events::Null.new, detect_conflicts: true)
        @guid               = guid
        @archive_path       = archive_path
        @migration_path     = migration_path
        @events             = events
        @cache              = GitHub::Migrator::Cache.new
        @current_migration  = MigratableResource.for_guid(guid)
        @warnings           = []
        @detect_conflicts   = detect_conflicts
      end

      # Public: Prepare the import by creating a MigratableResource in the target
      # schema for every model in the archive at the given archive_path.
      def call
        verify_new_guid!
        extract_archive(archive_path, migration_path)
        verify_schema_version!

        GitHub::Migrator::MigratableModels::MIGRATABLE_MODELS.each &method(:create_migratable_resources)

        report_options = { warnings: warnings }

        if @detect_conflicts
          report_options[:conflicts] = conflicts?
        end

        GitHub::Migrator::MigrationReporter.migrator_result(
          current_migration.will_create_model, report_options
        )
      ensure
        cleanup_after_migrator
        cache.clear
      end

      # Internal: Array of importer warnings collected while creating migratable
      # resources.
      #
      # Returns an Array.
      attr_accessor :warnings

      private

      attr_reader :cache, :events, :guid, :archive_path, :migration_path, :current_migration

      # Internal: Creates migratable resources for the migratable model using the
      # migratable resource batch service. Sets target urls using the url translator
      # if the schema supports it. Collects warnings from the importers.
      #
      # migratable_model - GitHub::Migrator::MigratableModel
      def create_migratable_resources(migratable_model)
        return unless migratable_model && migratable_model.importer
        model_type = migratable_model.model_type

        get_serialized_models_from_archive(model_type) do |serialized_models|
          serialized_models.each do |serialized_model|
            if translate_urls?
              serialized_model.update("target_url" => url_translator.translate(model_type, serialized_model["url"]))
            end
            migratable_resources_batch_service.add(serialized_model)
            self.warnings += migratable_model.importer.warnings_for(serialized_model, schema_version: archive_schema_version)
          end
        end

        migratable_resources_batch_service.complete
      end

      def schema_version
        @schema_version ||= GitHub::Migrator::SchemaVersion.new
      end

      # Internal: Creates and returns a GitHub::Migrator::BatchService for inserting serialized
      # models into the destination database as MigratableResources, to prepare for importing.
      #
      # BatchService#add will add a serialized model to a batch (Set), and when that batch reaches
      # a count of 1000, will execute the BatchService's block, given in its initializer, for every
      # member of the batch, and start again.
      #
      # The block will take each serialized_model (Hash) in the current batch and create a
      # MigratableResource, to prepare for final importing. This allows the migration to inspect for
      # conflicts and request resolutions from the user prior to creating the actual models in the
      # database during the final import process.
      #
      # BatchService#complete will iterate over the final batch of serialized_models, if there are
      # any, in the likely case that the total for the final batch didn't reach 1000.
      def migratable_resources_batch_service
        @migratable_resources_batch_service ||= GitHub::Migrator::BatchService.new do |serialized_models|
          migratable_resources_values = Arel::Nodes::ValuesList.new(
            serialized_models.map do |serialized_model|
              target_url = serialized_model["target_url"] if translate_urls?

              [
                guid,
                serialized_model["type"],
                serialized_model["url"],
                target_url,
                MigratableResource.states[:import],
                GitHub::SQL::ArelLiterals::NOW,
                GitHub::SQL::ArelLiterals::NOW
              ]
            end
          )

          ActiveRecord::Base.connected_to(role: :writing) do
            MigratableResource.connection.insert(
              Arel.sql(BATCH_INSERT_SQL, migratable_resources_values: migratable_resources_values)
            )
          end

          events.fire(:progress_with_count, serialized_models.size)
        end
      end

      # Internal: Verify that this `gh-migrator prepare` isn't reusing a guid from an earlier attempt.
      def verify_new_guid!
        return if @reuse_guid

        if MigratableResource.where(guid: guid).any?
          raise GitHub::Migrator::GuidCollision, "#{guid} is already in use and cannot be used for a new import."
        end
      end

      # TODO: Create a GitHub::Migrator::Schema class that can encapsulate extraction
      # creation, versioning, etc.
      #
      # Internal: Verify that the schema version in the archive matches what we expect.
      def verify_schema_version!
        raise GitHub::Migrator::UnsupportedArchive unless File.exist?("#{migration_path}/schema.json")

        unless schema_version.can_import?(archive_schema_version)
          raise GitHub::Migrator::UnsupportedSchemaVersion
        end
      end

      # Internal: Extract the schema version from the archive.
      def archive_schema_version
        if @archive_schema_version.nil?
          read_from_archive("schema.json") do |file|
            data = GitHub::JSON.parse(file.read)
            @archive_schema_version = data["version"]
          end
          @archive_schema_version ||= false
        end

        @archive_schema_version || nil
      end

      # Internal: Read the serialized models for model_type from the extracted
      # archive, yielding the block with the parsed contents of each file.
      #
      # model_type - String singular name of model.
      def get_serialized_models_from_archive(model_type)
        file_path = T.let(nil, T.untyped)
        begin
          pattern = "#{model_type.pluralize}_*.json"
          read_from_archive(pattern) do |file|
            file_path = file.path
            serialized_models = GitHub::JSON.parse(file.read)
            yield(serialized_models) unless serialized_models.empty?
          end
        rescue Errno::ENOENT => e
          # noop
        rescue NoMethodError => e
          GitHub.logger.error("JSON parse error",
            {
            :exception => e,
            "gh.migration_tools.migration.type" => "repo",
            "gh.migration_tools.migration.archive_file" => file_path,
            "code.function" => "get_serialized_models_from_archive",
            "code.namespace" =>  self.class.name,
            "gh.migration_tools.migration.guid" => guid,
           }
          )
          raise
        end
      end

      # Internal: Does this schema support translating urls?
      # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
      def translate_urls?
        @translate_urls ||= schema_version.can_translate_urls?(archive_schema_version)
      end
      # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

      # TODO: concflicts and conflicts? will have to be extracted into their own
      # service objects and reused here.
      #
      # Internal: Are there any conflicts in this migration?
      #
      # Returns a TrueClass or FalseClass.
      def conflicts?
        has_conflicts = T.let(false, T::Boolean)

        conflicts do |_model_type, _source_url, _target_url, _recommended_action|
          has_conflicts = true
          break
        end

        has_conflicts
      ensure
        cache.clear
      end

      # Internal: Calculate conflicting source and target urls and yield block with
      # model_type, source_url, target_url, and recommended_state.
      def conflicts
        GitHub::Migrator::MigratableModels::MIGRATABLE_MODELS.each do |migratable_model|
          next unless migratable_model.check_for_conflicts?

          model_url_service  = GitHub::Migrator::ModelUrlService.new(cache: cache)
          current_migration.
            by_model_type(migratable_model.model_type).
            not_mapped.
            not_final.
            find_each do |migratable_resource|
            # If this is a team or repository and the org it belongs to has been
            # mapped to an existing org rewrite the team or repository url with
            # the new orgs name otherwise use the original source_url.
            unrewritten_source_url = migratable_resource.target_url || migratable_resource.source_url
            rewritten_source_url = rewrite_source_url_for_target(migratable_resource, unrewritten_source_url)

            if model = model_url_service.model_for_url(rewritten_source_url)
              model_type = migratable_resource.model_type
              source_url = migratable_resource.source_url
              target_url = model_url_service.url_for_model(model)
              action     = migratable_model.recommended_action

              yield(model_type, source_url, target_url, action, nil)
            elsif !model_url_service.url_valid?(unrewritten_source_url)
              model_type = migratable_resource.model_type
              source_url = migratable_resource.source_url

              yield(model_type, source_url, nil, :rename, "Invalid value in url")
            end
          end
        end
      ensure
        cache.clear
      end

      # Internal: Build instance of UrlTranslator with correct from template.
      def url_translator
        @url_translator ||= begin
          if templates = archive_url_templates
            GitHub::Migrator::UrlTranslator.new(from: templates)
          else
            GitHub::Migrator::UrlTranslator.new
          end
        end
      end

      # Internal: Rewrite the source url, mapping the source db's org names to the target
      # db's org names. This accounts for any renaming of Organizations that takes place
      # during the import, keeping both reference URLs and org/team org/repo relationships
      # consistent.
      #
      def rewrite_source_url_for_target(migratable_resource, unrewritten_source_url)
        case migratable_resource.model_type
        when "team"
          _, host, org_name, team_name = GitHub::Migrator::TEAM_URL_REGEX.match(unrewritten_source_url).to_a
          if org = current_migration.by_source_url("#{host}/#{org_name}").model
            "#{host}/orgs/#{org.login}/teams/#{team_name}"
          end
        when "repository"
          _, host, org_name, repo_name = GitHub::Migrator::REPO_URL_REGEX.match(unrewritten_source_url).to_a
          if org = current_migration.by_source_url("#{host}/#{org_name}").model
            "#{host}/#{org.login}/#{repo_name}"
          end
        else
          unrewritten_source_url
        end
      end
    end
  end
end
