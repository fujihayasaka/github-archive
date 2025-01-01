# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class ArchiveImporter
      include MigratorHelper
      extend T::Helpers
      extend T::Sig

      attr_reader :guid, :archive_path, :migration_path, :migration_source, :actor, :event_handler, :per_second, :skip_import_errors
      def initialize(guid:, archive_path:, migration_path:, actor:, migration_source:, owner: nil, event_handler: Events::Null.new, per_second: nil, skip_import_errors: false)
        @guid = guid
        @archive_path = archive_path
        @migration_path = migration_path
        @actor = actor
        @owner = owner
        @event_handler = event_handler
        @per_second = per_second
        @skip_import_errors = skip_import_errors
        @migration_source = migration_source
      end

      def call
        raise EmptyMigration unless current_migration.exists?

        send_migration_importer_start_metrics

        extract_archive(archive_path, migration_path)

        event_handler.fire(:sample_resource_usage)
        importing_mode do
          import_models
          post_process_models

          # Suspend users that don't belong to repository owning orgs or are
          # repository collaborators.
          UserSuspender.process(current_migration)
          event_handler.fire(:progress_with_count, 1)
        end

        # Index models that are imported using the direct insert approach.
        ModelIndexer.process(current_migration)
        event_handler.fire(:progress_with_count, 1)

        event_handler.fire(:sample_resource_usage)
        MigrationReporter.migrator_result(current_migration.migrated)
      ensure
        cleanup_after_migrator
        cache.clear
      end

      private

      def send_migration_importer_start_metrics
        # datadog metrics
        tags = {
          importer: "eci",
          migration_source: migration_source,
          owner_id: @owner&.id,
          guid: guid
        }
        GitHub.dogstats.increment(
          "importer.started.increment",
          tags: tags
        )
      end

      def import_models
        # Import (and optionally rename), map, and merge each model that has
        # a migratable_model.importer.
        MIGRATABLE_MODELS.each do |migratable_model|
          next unless migratable_model && migratable_model.importer

          importer = migratable_model.importer.new(
            actor:             actor,
            current_migration: current_migration,
            migration_path:    migration_path,
            model_url_service: model_url_service,
            cache:             cache,
            migration_guid:    guid
          )

          get_serialized_models_from_archive(migratable_model.model_type) do |serialized_models|
            event_handler.fire(:sample_resource_usage)
            migratable_resources_by_url = migratable_resources_for_serialized_models_by_url(serialized_models)
            models_by_id = models_for_migratable_resources_by_id(migratable_resources_by_url.values)

            serialized_models.each do |attributes|
              # This throttler is used on GitHub Enterprise and can be set
              # manually from the gh-migrator command line utility.
              per_second_throttler.throttle do
                begin
                  migratable_resource = migratable_resources_by_url[attributes["url"]]

                  unless migratable_resource
                    log_error_and_fail_model(StandardError.new("Skipping due to URL not found on model"), migratable_resource, attributes)
                    next
                  end

                  migratable_resource.model_type = attributes["type"]
                  MigratableResource.throttle_with_retry do
                    migratable_resource.save
                  end

                  tags = {
                    model_type: migratable_resource.model_type,
                    guid: guid,
                    owner_id: @owner&.id,
                    migration_source: migration_source
                  }

                  GitHub.dogstats.increment(
                    "migrator.import.import_model.increment",
                    tags: tags
                  )

                  GitHub.dogstats.distribution_time("migrator.import.import_model.dist.time", tags: tags) do
                    # This is a model specific throttler that is used while importing records
                    # on our internal infrastucture (currently used for SaaS migrations).
                    #
                    # On Enterprise this throttle will just yield immediately.
                    model_or_importer_result = migratable_model.model_class.throttle_with_retry(max_retry_count: 8) do
                      import_map_or_merge(
                        models_by_id[migratable_resource.model_id],
                        migratable_resource,
                        importer,
                        attributes,
                      )
                    end

                    # set default
                    model = nil

                    if model_or_importer_result.is_a?(ImporterResult)
                      if model_or_importer_result.success?
                        model = model_or_importer_result.model
                      else
                        migratable_resource.warning = model_or_importer_result.warning
                        migratable_resource.failed_import!
                        next
                      end
                    # Backwards compatability to models that don't yet support ImporterResult
                    else
                      model = model_or_importer_result
                    end

                    next unless model

                    if model.present? && model.persisted?
                      migratable_resource.model_id = model.id
                      migratable_resource.target_url = url_for_model(model)
                    end

                    MigratableResource.throttle_with_retry do
                      migratable_resource.save
                    end

                    event_handler.fire(:progress_with_count, 1)
                  end
              rescue AssociationFailed => error
                log_error_and_fail_model(error, migratable_resource, attributes)
              # We really should not be doing blind rescues here.
              # TODO: Remove blind rescue and implement a list of acceptable errors that we
              # can raise/skip
              rescue => error # rubocop:todo Lint/GenericRescue
                log_error_and_fail_model(error, migratable_resource, attributes)

                raise error unless skip_import_errors
                end
              end
            end
          end
        end
      end

      def post_process_models
        # Skip joins for large migrations where the actor has the gh_migrator_skip_post_processor_joins feature flag
        skip_joins = @actor.feature_enabled?(:gh_migrator_skip_post_processor_joins)

        # Post process each model that has a migratable_model.post_processor.
        MIGRATABLE_MODELS.each do |migratable_model|
          next unless migratable_model && migratable_model.post_processor

          model_type = migratable_model.model_type
          post_processor = migratable_model.post_processor.new(
            current_migration:     current_migration,
            user_content_rewriter: user_content_rewriter,
          )

          get_serialized_models_from_archive(model_type) do |serialized_models|
            migratable_resources_by_url = migratable_resources_for_serialized_models_by_url(serialized_models)
            models_by_id = models_for_migratable_resources_by_id(migratable_resources_by_url.values, joins: post_processor.joins, skip_joins: skip_joins)

            serialized_models.each do |attributes|
              # This throttler is used on GitHub Enterprise and can be set
              # manually from the gh-migrator command line utility.
              per_second_throttler.throttle do
                migratable_resource = migratable_resources_by_url[attributes["url"]]

                begin
                  GitHub.dogstats.distribution_time("migrator.import.post_process_models.dist.time", tags: ["model_type:#{migratable_resource.model_type}", "guid:#{guid}", "owner_id:#{@owner&.id}"]) do
                    # This is a model specific throttler that is used while importing records
                    # on our internal infrastucture (currently used for SaaS migrations).
                    #
                    # On Enterprise this throttle will just yield immediately.
                    migratable_model.model_class.throttle_with_retry do
                      post_processor.process(models_by_id[migratable_resource.model_id], attributes, batch_load_associations: skip_joins)
                    end
                  end
                rescue NoMethodError => error
                  GitHub.logger.error("Skipping due to undefined method", {
                    :exception => error,
                    "code.function" => "post_process_models",
                    "code.namespace" => "GitHub::Migrator::ArchiveImporter",
                    "gh.migration_tools.migration.type" => "repo",
                    "gh.migration_tools.migration.model.source_url" => attributes["url"],
                    "gh.migration_tools.migration.resolution" => "skipped",
                    "gh.migration_tools.migration.guid" => guid,
                    }
                  )
                end

                event_handler.fire(:progress_with_count, 1)
              end
            end
          end
        end
      end

      def import_map_or_merge(model_by_id, migratable_resource, importer, attributes)
        model_methods = {
          import_migratable_resource: [
            model_by_id,
            migratable_resource,
            importer,
            attributes,
          ],
          merge_migratable_resource: [
            model_by_id,
            migratable_resource,
            importer,
            attributes,
          ],
          map_migratable_resource: [
            model_by_id,
            migratable_resource,
          ],
          skip_migratable_resource: [
            migratable_resource,
            attributes,
          ],
          merge_owners_team: [
            model_by_id,
            migratable_resource,
            importer,
            attributes,
          ],
        }
        # We don't want to continue calling methods once one returns a model, so
        # this will abort once one is returned.
        model_methods.each do |method, args|
          model_or_importer_result = T.unsafe(self).send(method, *args)
          return model_or_importer_result if model_or_importer_result
        end
        nil
      end

      def import_migratable_resource(model_by_id, migratable_resource, importer, attributes)
        return unless migratable_resource.should_import?(model_by_id)
        model_or_importer_result = importer.import(attributes, target_url: migratable_resource.target_url)

        model = model_or_importer_result.is_a?(ImporterResult) ? model_or_importer_result.model : model_or_importer_result

        if model.present?
          if renaming?(migratable_resource)
            migratable_resource.renamed
          else
            migratable_resource.imported
          end
        else
          if renaming?(migratable_resource)
            migratable_resource.failed_rename
          else
            migratable_resource.failed_import
          end
        end
        model_or_importer_result
      end

      def merge_migratable_resource(model_by_id, migratable_resource, importer, attributes)
        return unless migratable_resource.should_merge?(model_by_id)
        model = importer.merge(attributes, model_by_id)
        if model.present?
          migratable_resource.merged
        else
          migratable_resource.failed_merge
        end
        model
      end

      def map_migratable_resource(model_by_id, migratable_resource)
        return unless migratable_resource.should_map?(model_by_id)
        migratable_resource.mapped
        model_by_id
      end

      def skip_migratable_resource(migratable_resource, attributes)
        return unless migratable_resource.skip?

        model = migratable_resource.model

        unless model
          model = Mannequin.new(
            source_login: target_login_for(migratable_resource, attributes),
            owner: migration.owner,
          )

          emails = attributes["emails"]

          if emails.present?
            emails.each do |email|
              if email["address"] =~ User::EMAIL_REGEX && !UserEmail::DisposableEmailsDependency.disposable_email?(email["address"])
                model.emails.new(
                  email:   email["address"],
                  primary: email["primary"],
                )
              else
                model.emails.new(
                  email:   "#{model.source_login}-#{SecureRandom.alphanumeric(6).downcase}@migrations.noreply.#{GitHub.host_name}",
                  primary: email["primary"],
                )
              end
            end
          end

          begin
            model.save!
          rescue ActiveRecord::ActiveRecordError => exception
            migratable_resource.failed_skip
            raise(FailedSkip, exception)
          end
        end

        migratable_resource.skipped

        model
      end

      def target_login_for(migratable_resource, attributes)
        migratable_resource.target_url&.split("/")&.last || attributes["login"]
      end

      def migration
        @migration ||= ::Migration.find_by(guid: guid)
      end

      def merge_owners_team(model_by_id, migratable_resource, importer, attributes)
        return unless migratable_resource.should_merge_owners_team?
        model = importer.merge(attributes, model_by_id)
        if model.present?
          migratable_resource.merged
        else
          migratable_resource.failed_merge
        end
        model
      end

      def log_error_and_fail_model(error, migratable_resource, attributes)
        repo_params = repo_url_params(migratable_resource, attributes) || {}
        GitHub.logger.error("Failed to import model", {
          :exception => error,
          "code.function" => "log_error_and_fail_model",
          "code.namespace" => "GitHub::Migrator",
          "gh.migration_tools.migration.type" => "repo",
          "gh.migration_tools.migration.model.name" => attributes["type"],
          "gh.migration_tools.migration.migratable_resource_id" => migratable_resource.try(:id),
          "gh.migration_tools.migration.model.id" => migratable_resource.try(:model_id),
          "gh.migration_tools.migration.source_owner" => repo_params["owner"],
          "gh.migration_tools.migration.source_repository" => repo_params["repository"],
          "gh.migration_tools.migration.model.source_url" => attributes["url"],
          "gh.migration_tools.migration.model.target_url" => migratable_resource.try(:target_url),
          "gh.migration_tools.migration.model.translator_url" => translator_url(migratable_resource),
          "gh.migration_tools.migration.model.state" => migratable_resource.try(:state),
          "gh.migration_tools.migration.model.resolution" => "failed",
          "gh.migration_tools.migration.guid" => guid
          }
        )

        if migratable_resource
          migratable_resource.failed_import unless migratable_resource.failed?
          migratable_resource.warning = error.message
          MigratableResource.throttle_with_retry do
            migratable_resource.save
          end
        end
      end

      def repo_url_params(migratable_resource, attributes)
        return {} unless migratable_resource
        # Attachments aren't tied to a specific repo so return empty hash
        return {} if %w(attachment repository_file).include?(migratable_resource.model_type)

        url_translator.extract(
          model_url_template(migratable_resource.model_type, attributes) || "",
          migratable_resource.source_url
        )
      end

      def renaming?(migratable_resource)
        if translate_urls?
          migratable_resource.rename?
        else
          migratable_resource.target_url.present?
        end
      end

      def translator_url(migratable_resource)
        if translate_urls?
          url_translator.translate(
            migratable_resource.model_type, migratable_resource.source_url
          )
        end
      end
    end
  end
end
