# typed: true
# frozen_string_literal: true

require "csv"

# Exporter is a service object that iterates through a migration's MigratableResources,
# serializes the models to JSON and writes them to a file, and archives any related files
# such as git repositories, file attachments or release archives.
#
module GitHub
  class Migrator

    MAX_EXPORT_ARCHIVE_SIZE = 40.gigabytes
    class Exporter
      include GitHub::Migrator::TarUtils

      # Standard batch size for metadata archive files
      METADATA_BATCH_SIZE = 100

      # Models such as attachments and repository files should have fewer records per archive file
      CUSTOM_METADATA_BATCH_SIZE = 50

      MODEL_TYPES_WITH_CUSTOM_BATCH_SIZE = %w[attachment repository_file]

      # These models are archived in subdirectories
      ARCHIVE_CONTENT_DIRECTORIES = %w[attachments releases repository_files repositories]

      # Public: Instantiates an Exporter for the migration represented by guid.
      #
      # guid                  - A unique identifier representing the migration to be
      #                         exported.
      # migration_path        - The path that the JSON file containing all of the
      #                         serialized models, and all of the dependent files
      #                         (repos, attachments, releases, wikis) will be stored
      #                         in order to create the final archive
      # archive_export_path   - The filepath where the final archive (tarball) will
      #                         be located.
      # actor                 - The actor performing the export, must have read
      #                         permissions for all of the models being exported.
      # options values:
      # events:               - An instance of GitHub::Migrator::Events that will notify
      #                         its subscribers of progress.
      # exclude_git_data:    - A boolean indicating whether or not to archive repo git data
      #                        for Octoshift metadata exports (default: false)
      #
      def initialize(guid:, migration_path:, archive_export_path:, actor:, owner:, options: nil)
        options ||= {}
        @guid                 = guid
        @migration_path       = migration_path
        @archive_export_path  = archive_export_path
        @actor                = actor
        @owner                = owner
        @events               = options.fetch(:events) { GitHub::Migrator::Events::Null.new }
        @exclude_git_data     = options.fetch(:exclude_git_data) { false }
        @org_metadata_only    = options.fetch(:org_metadata_only) { false }
        @cache                = GitHub::Migrator::Cache.new
        @schema_version       = GitHub::Migrator::SchemaVersion.new
        @model_url_service    = GitHub::Migrator::ModelUrlService.new(cache: cache)
        @current_migration    = MigratableResource.for_guid(guid)
      end

      # Public: Execute the action. Serializes all of the MigratableResources for the
      # migration represented by guid and all of its file dependencies, then creates
      # the final archive as a tarball at archive_export_path
      #
      # Raises an EmptyMigration if no MigratableResources exist for the guid.
      #
      # Returns a Hash with a count of each model type that was exported.
      def call
        raise GitHub::Migrator::EmptyMigration unless current_migration.exists?

        FileUtils.mkdir_p(migration_path) unless File.exist?(migration_path)

        GitHub::Migrator::MigratableModels::MIGRATABLE_MODELS.each do |migratable_model|
          serialize_model_and_dependent_files(migratable_model)
        end

        write_schema_version_to_archive
        write_audit_log_to_archive
        create_archive(migration_path, archive_export_path)

        log_archive_contents

        GitHub::Migrator::MigrationReporter.migrator_result(
          current_migration.by_states(:exported),
          archive_path: archive_export_path.to_s,
        )
      ensure
        FileUtils.rm_rf(migration_path, secure: true)

        # Forecully remove the archive staging dirctory if FileUtils wasn't able to nuke it
        if File.exist?(migration_path)
          options = ["-rf", "#{migration_path}"]

          child = Progeny::Command.new("rm", *options)
          raise GitHub::Migrator::ExportFailure, "Unable to prune staging directory: #{child.err}" unless child.success?
        end

        cache.clear
      end

      private

      attr_reader :model_url_service, :migration_path, :cache, :guid, :actor, :owner, :current_migration, :events, :schema_version, :archive_export_path, :exclude_git_data, :org_metadata_only

      # Take the given MigratableModel and retrieve its serializer and archiver if it has one.
      #
      # Iterate through all of the MigratableResources for this migration guid and given
      # MigratableModel, serialize the related models to the JSON file, and write any related
      # files to the filesystem at migration_path.
      #
      # Copy files to migration_path, to prep for archiving (repositories, attachments, releases.).
      def serialize_model_and_dependent_files(migratable_model)
        serializer = migratable_model.serializer.new(
          model_url_service: model_url_service,
          actor: actor,
          owner: owner,
          org_metadata_only: org_metadata_only
        )
        archiver = migratable_model.build_archiver(actor: actor, migration_path: migration_path)
        model_type = migratable_model.model_type
        batch = 1

        migratable_resources_by_model_type_in_batches(model_type) do |migratable_resources|
          models = MigratableResource.models_for_migratable_resources(migratable_resources, scope: serializer.scope)
          model_ids = models.pluck(:id)
          models_mrs = migratable_resources.select { |migratable_resource| model_ids.include?(migratable_resource.model_id) }
          deleted_models_mrs = migratable_resources.reject { |migratable_resource| model_ids.include?(migratable_resource.model_id) }
          failed_serialized_models = []

          serialized_models = models.map do |model|
            begin
              serialized_model = serializer.serialize(model)

              if serialized_model.nil?
                failed_serialized_models << model
                nil
              else
                serialized_model
              end
            rescue => e # rubocop:todo Lint/GenericRescue
              # Rescue from any serialization errors and save these models to a separate array
              failed_serialized_models << model
              nil
            end
          end.compact

          begin
            write_serialized_models_to_migration_path(serialized_models, model_type, batch)
          rescue ::JSON::GeneratorError, ::Encoding::UndefinedConversionError => e
            set_state_on_migratable_resources(:failed_export, migratable_resources)
            raise GitHub::Migrator::ExportFailure.new("error exporting #{model_type} (model ids: #{migratable_resources.map(&:model_id)}): (#{e.class}) #{e}")
          end

          if archiver
            models.each do |model|
              archiver.save(model)
              # after each model check the size of uncompressed directory:
              uncompressed_dir_size = get_dir_size(migration_path)

              # gz compression rate is 75%-95% but assuming majority of files consuming
              # large amounts of storage are images and other binary files so we set
              # threshold conservatively to 50% compression rate.
              # This means we allow uncompressed directory to grow 2x of the MAX_EXPORT_ARCHIVE_SIZE
              # before we raise an error.
              if uncompressed_dir_size * 0.5 > MAX_EXPORT_ARCHIVE_SIZE
                raise GitHub::Migrator::ExportFailure.new(
                  "Export size #{uncompressed_dir_size} exceeded maximum size of #{MAX_EXPORT_ARCHIVE_SIZE} bytes. We assume 50% compression rate.")
              end

            end unless model_type == "repository" && exclude_git_data
          end unless org_metadata_only

          # Fetch migratable resources with serialization issues
          failed_serialized_models_mrs = models_mrs.select { |migratable_resource| failed_serialized_models.pluck(:id).include?(migratable_resource.model_id) }
          successfully_serialized_model_mrs = models_mrs.reject { |migratable_resource| failed_serialized_models_mrs.include?(migratable_resource) }

          set_state_on_migratable_resources(:exported, successfully_serialized_model_mrs) unless successfully_serialized_model_mrs.empty?
          set_state_on_migratable_resources(:failed_export, deleted_models_mrs, "Model could not be found. This model was likely deleted prior to export.") if deleted_models_mrs.any?
          set_state_on_failed_migratable_resources(failed_serialized_models_mrs, models, serializer) if failed_serialized_models_mrs.any?

          batch += 1

          events.fire(:progress_with_count, migratable_resources.size)
        end
      end

      def file_batch_size(model_type)
        return CUSTOM_METADATA_BATCH_SIZE if MODEL_TYPES_WITH_CUSTOM_BATCH_SIZE.include?(model_type)

        METADATA_BATCH_SIZE
      end

      # Internal: Writes the JSON representing the current batch of serialized models to
      # migration_pathto a filename indicating the model type and batch number, to the
      # folder at migration_path, for instance:
      #
      # repositories_000003.json
      #
      # serialized_models:    - An array representing the current batch of serialized models
      # model_type            - The downcased string class name of the models (will be pluralized)
      # batch                 - The number of the current batch
      def write_serialized_models_to_migration_path(serialized_models, model_type, batch)
        return if serialized_models.empty?

        filename = "#{model_type.pluralize}_#{batch.to_s.rjust(6, '0')}.json"
        File.open(File.join(migration_path, filename), "w") do |file|
          file.write(::JSON.pretty_generate(serialized_models.as_json))
        end
      end

      # Internal: Set state on migratable resources. It's necessary to use the write db
      # here because the gh-migrator cli otherwise is set to use the read-only db.
      #
      # state                - Symbol state for MigratableResource.
      # migratable_resources - Array of MigratableResource instances.
      def set_state_on_migratable_resources(state, migratable_resources, warning = nil)
        ActiveRecord::Base.connected_to(role: :writing) do
          current_migration.set_state!(state, migratable_resources, warning)
        end
      end

      # Internal: Set state on migratable resources that failed to serialize, including a warning for validation errors.
      #
      # failed_migratable_resources - Array of MigratableResource instances that failed to serialize.
      # models                      - Array of models that were serialized.
      # serializer                  - The BaseSerializer instance on the migratable model.
      def set_state_on_failed_migratable_resources(failed_migratable_resources, models, serializer)
        batch_mapper = GitHub::Migrator::MigratableResourceBatchMapper.new(guid: guid)

        failed_migratable_resources.each do |migratable_resource|
          model = models.find { |m| m.id == migratable_resource.model_id }
          critical_validation_errors = serializer.critical_validation_errors(model)

          migratable_resource.warning =
            if critical_validation_errors.any?
              "Model could not be serialized due to validation errors: #{critical_validation_errors.full_messages.to_sentence}"
            else
              "Model could not be serialized due to serialization errors"
            end

          migratable_resource.state = :failed_export

          batch_mapper.add(migratable_resource)
        end
        batch_mapper.complete
      end

      # Internal: Writes the current version of gh-migrator's schema to the archive.
      # The schema version allows the migrator to understand what it can and can't
      # import from a given archive.
      #
      # See: GitHub::Migrator::SchemaVersion
      def write_schema_version_to_archive
        File.open(File.join(migration_path, "schema.json"), "w") do |file|
          info = {
            version: schema_version.for_export(current_migration),
            github_sha: GitHub.current_sha,
          }
          file.write info.to_json
        end
      end

      # Internal: Writes the log file to the archive.
      # This will include all migratable_resources that are in a failed state.
      def write_audit_log_to_archive
        scope = MigratableResource.for_guid(guid)
        failed_mrs = scope.failed
        write_to_csv(failed_mrs) unless failed_mrs.empty?
      end

      # Internal: Writes migratable_resources to a csv file in the archive.
      def write_to_csv(migratable_resources)
        CSV.open(File.join(migration_path, "audit_log.csv"), "w") do |csv|
          csv << %w[model_name model_id source_url state warning]

          migratable_resources.find_each do |migratable_resource|
            model_type = migratable_resource.model_type
            model_id   = migratable_resource.model_id
            source_url = migratable_resource.source_url
            state      = migratable_resource.state
            warning    = migratable_resource.warning

            csv << [model_type, model_id, source_url, state, warning]
          end
        end
      end

      # Internal: Emits a log containing the archive size, current migration, and content of archive subdirectories
      def log_archive_contents
        uncompressed_archive_size = get_dir_size(migration_path)
        compressed_archive_size = File.size(archive_export_path)

        log_info = {
          "migration_guid" => guid,
          "compressed_archive_bytes" => compressed_archive_size,
          "uncompressed_archive_bytes" => uncompressed_archive_size,
        }

        ARCHIVE_CONTENT_DIRECTORIES.each do |dir|
          sub_dir_path = File.join(migration_path, dir)
          dir_size = get_dir_size(sub_dir_path)
          log_info["#{dir}_bytes"] = dir_size
        end

        GitHub.logger.info("Export archive generated", log_info)
      end

      def get_dir_size(path)
        Pathname.new(path).glob("**/*").select(&:file?).sum(&:size)
      end

      def migratable_resource_ids_by_model_type(model_type)
        ids = []
        last_batch_id = T.let(0, T.untyped)

        batch_scope = current_migration.by_model_type(model_type).limit(100_000).order(:id)
        batch_ids = batch_scope.where("id > ?", last_batch_id).pluck(:id)

        while batch_ids.any?
          ids.concat(batch_ids)
          last_batch_id = batch_ids.last

          batch_ids = batch_scope.where("id > ?", last_batch_id).pluck(:id)
        end

        ids
      end

      def migratable_resources_by_model_type_in_batches(model_type, &block)
        migratable_resource_ids_by_model_type(model_type).each_slice(file_batch_size(model_type)) do |migratable_resource_ids|
          block.call(MigratableResource.where(id: migratable_resource_ids).to_a)
        end
      end
    end
  end
end
