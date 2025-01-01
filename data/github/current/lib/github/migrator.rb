# typed: true
# frozen_string_literal: true

require "pathname"
require "set"
require "github/throttler"
require "github/rsync"

# GitHub::Migrator is a tool for migrating repositories and their dependencies
# from one GitHub instance to another.
#
# The functionality being developed here is based on this UI demo:
#   https://github.com/github/github/pull/36686
#
# Exporting results in a archive that can be copied from the source to the
# target that is then used as the input to the import process.

require "github/migrator/errors"
require "github/migrator/tar_utils"
require "github/migrator/download_helpers"
require "github/migrator/importer"
require "github/migrator/repo_helpers"
require "github/migrator/migratable_models"
require "github/migrator/migrator_helper"
require "github/migrator/events"

module GitHub
  class Migrator
    # These files should not be managed by the _Rails_ autoloader, but instead
    # the _Ruby_ autoload mechanism.
    autoload :Api, "github/migrator/api"
    autoload :Cache, "github/migrator/cache"
    autoload :CliEvents, "github/migrator/cli_events"
    autoload :LoggerHelpers, "github/migrator/logger_helpers"
    autoload :BatchService, "github/migrator/batch_service"
    autoload :SchemaVersion, "github/migrator/schema_version"
    autoload :MigratableResourceExportBuilder, "github/migrator/migratable_resource_export_builder"
    autoload :MigratableResourceBatchMapper, "github/migrator/migratable_resource_batch_mapper"
    autoload :MigratedRepositoriesUnlocker, "github/migrator/migrated_repositories_unlocker"
    autoload :ModelUrlService, "github/migrator/model_url_service"
    autoload :ModelForUrl, "github/migrator/model_url_service"
    autoload :CaseInsensitiveHash, "github/migrator/case_insensitive_hash"
    autoload :UserContentRewriter, "github/migrator/user_content_rewriter"
    autoload :ImportMapper, "github/migrator/import_mapper"
    autoload :ImportPreparer, "github/migrator/import_preparer"
    autoload :ImporterResult, "github/migrator/importer_result"
    autoload :Exporter, "github/migrator/exporter"
    autoload :AttachmentMigrator, "github/migrator/attachment_migrator"
    autoload :ModelIndexer, "github/migrator/model_indexer"
    autoload :UserSuspender, "github/migrator/user_suspender"
    autoload :DefaultUrlTemplates, "github/migrator/default_url_templates"
    autoload :GitLabUrlTemplates, "github/migrator/url_templates"
    autoload :BitBucketServerUrlTemplates, "github/migrator/url_templates"
    autoload :UrlTranslator, "github/migrator/url_translator"
    autoload :MigrationReporter, "github/migrator/migration_reporter"
    autoload :ExportPreparer, "github/migrator/export_preparer"
    autoload :ExperimentalBatchExportPreparer, "github/migrator/experimental_batch_export_preparer"
    autoload :DatabricksIssue9713ExportPreparer, "github/migrator/databricks_issue_9713_export_preparer"
    autoload :OrganizationExportPreparer, "github/migrator/organization_export_preparer"
    autoload :ConflictsDetector, "github/migrator/conflicts_detector"
    autoload :MigrationFileUploader, "github/migrator/migration_file_uploader"
    autoload :ImportMapper, "github/migrator/import_mapper"
    autoload :ArchiveImporter, "github/migrator/archive_importer"
    autoload :KV, "github/migrator/kv"

    include ActionView::Helpers::DateHelper
    include MigratorHelper
    include Events

    CACHE_SIZE = 100_000

    def initialize(options = nil)
      options = options || {}

      @guid         = options[:guid]
      @actor        = options[:actor]
      @owner        = options[:owner]
      @archive_path = options[:archive_path]
      @migration_path = options[:migration_path]
      @archive_export_path = options[:archive_export_path]
      @per_second   = options[:per_second]
      @reuse_guid   = options.fetch(:reuse_guid) { false }
      @skip_import_errors = options[:skip_import_errors]
      @exclude_git_data   = options.fetch(:exclude_git_data) { false }
      @org_metadata_only = options.fetch(:org_metadata_only) { false }
      @exclude_metadata = options.fetch(:exclude_metadata) { false }
    end

    # Public: The guid used to reference a migration. This is the unique
    # identifier for the migration.
    #
    # Returns a String.
    attr_reader :guid

    # Public: Prepares export for the model collection
    def prepare_export!(models)
      models.map { |model| add_to_export(url_for_model(model)) }
    end

    # Public: Prepare export for the model represented by the url and all of
    # its dependencies (associated models).
    #
    # url - String url of Repository
    #
    # Returns a Hash.
    def add_to_export(url, options = nil, events = Events::Null.new)
      options ||= {}
      options[:events] = events
      repository = model_url_service.model_for_url(url)
      export_preparer_klass(repository).new(repository: repository, guid: guid, options: options).call
    end

    # Public: Prepare export for the user represented by the url
    #
    # url_or_user - String url or ActiveRecord model of User or Organization
    #
    # Returns a Hash.
    def add_user_to_export(url_or_user, options = nil, events = Events::Null.new)
      if url_or_user.is_a?(String)
        user = model_url_service.model_for_url(url_or_user)
      else
        user = url_or_user
      end

      @export_builder ||= GitHub::Migrator::MigratableResourceExportBuilder.new \
        guid: guid,
        model_url_service: model_url_service,
        progress: lambda { |*x| events.fire(*x) }

      unless exclude_metadata
        add_repository_advisories(@export_builder, user)
      end

      @export_builder.add_now(user)
    end

    # Public: Prepare export for the Organization
    #
    # organization - The Organization to export
    #
    # Returns a Hash.
    def add_organization_to_export(organization, options = nil, events = Events::Null.new)
      GitHub::Migrator::OrganizationExportPreparer.new(organization: organization, guid: guid, options: options).call
    end

    # Public: Pulls all repository advisories authored by User
    # and adds them to the export.
    #
    # export_builder - export builder for the User
    # user - User model to pull advisories for
    #
    # Returns a Hash
    def add_repository_advisories(export_builder, user)
      # TODO how should we safeguard this more?
      advisories = RepositoryAdvisory.where(author_id: user.id)

      advisories.find_each do |advisory|
        next unless advisory.readable_by?(user)
        export_builder.add(advisory)
      end

      export_builder.complete
    end

    # Public: Set the location of where the repository will be migrated to in
    # order to be displayed to users. Does not functionally impact the migration.
    #
    # url - String url of the source Repository
    # options[:target_url] - String url of the target Repository
    #
    # Returns a Boolean or raises error on failure
    def set_exported_to_url(url, options = {})
      if repository = model_url_service.model_for_url(url)
        verify_target_url!(options[:target_url])
        repository.set_repository_exported_to_url(options[:target_url])
      end
    end

    # Public: Exports models and associated records represented by
    # MigratableResource records created with #add(url).
    #
    # Returns a Hash.
    def export!
      options ||= {}
      options[:exclude_git_data] = exclude_git_data
      options[:org_metadata_only] = org_metadata_only

      GitHub::Migrator::Exporter.new(
        guid: guid,
        migration_path: migration_path,
        archive_export_path: archive_export_path,
        actor: actor,
        owner: owner,
        options: options).call
    end

    # Public: Prepare import of models from source.
    #
    # archive_path - Pathname or String
    #
    # Returns a Hash.
    def prepare_import(events = Events::Null.new)
      ImportPreparer.new(
        archive_path: archive_path,
        migration_path: migration_path,
        guid: guid,
        events: events,
      ).call
    end

    # Team and repo url regular expression used for detecting conflicts when an
    # org being migrated is mapped to an existing org.
    TEAM_URL_REGEX = /(https?\:\/\/[^\/]+)\/orgs\/([^\/]+)\/teams\/(.+)/
    REPO_URL_REGEX = /(https?\:\/\/[^\/]+)\/([^\/]+)\/(.+)/

    # Public: Calculate conflicting source and target urls and yield block with
    # model_type, source_url, target_url, and recommended_state.
    #
    # Note: This iterates through every MigratableResource record for a
    # a migration so the larger the migration the longer it will take. In the
    # future it may make sense to look at memoizing the calculated result.
    #
    # TODO: This method is getting very long, let's look into refactoring it.
    def conflicts(organization: nil)
      ConflictsDetector.new(
        guid: guid,
        archive_url_templates: cached_url_templates,
        organization: organization,
      ).call do |model_type, source_url, target_url, action, notes|
        yield(model_type, source_url, target_url, action, notes)
      end
    end

    # Public: Are there any conflicts in this migration?
    #
    # Returns a TrueClass or FalseClass.
    def conflicts?(organization: nil)
      ConflictsDetector.new(
        guid: guid,
        archive_url_templates: cached_url_templates,
        organization: organization,
      ).conflicts?
    end

    # Public: Maps model from source to existing or new model at target.
    #
    # source_url - String url of model at source
    # target_url - String url of model at target
    # action     - (optional) Symbol of action to take in mapping.
    #
    #   Actions
    #     - :map (default) maps source_url to existing target_url
    #     - :merge merges model being imported with existing model
    #     - :rename when imported model is being renamed
    #       (rename is automatically set if target_url doesn't belong to an
    #        existing model)
    #
    # Returns a TrueClass.
    def map(source_url, target_url, action = nil, model_type = nil, organization: nil, batch_mappings: false)
      import_mapper.call(
        source_url,
        target_url,
        action,
        model_type,
        organization:   organization,
        batch_mappings: batch_mappings,
      )
    end

    # Public: Imports the models from the source.
    #
    # archive_path - Pathname or String
    #
    # Returns a Hash.
    def import!
      # TODO: Move me into ArchiveImport when conflicts become a service
      raise UnresolvedConflicts if conflicts?

      migration_source = migration_source_from_url_templates(cached_url_templates)

      archive_importer = GitHub::Migrator::ArchiveImporter.new(
        guid: guid,
        archive_path: archive_path,
        migration_path: migration_path,
        actor: actor,
        event_handler: self,
        per_second: per_second,
        skip_import_errors: skip_import_errors,
        owner: owner,
        migration_source: migration_source
      )

      archive_importer.call
    end

    # Public: Unlock migrated repositories.
    def unlock!
      MigratedRepositoriesUnlocker.call(guid: guid)
    end

    # Public: Get number of iterations that will occur for export or import.
    def total_records_count(action)
      case action
      when :export
        current_migration.count
      when :import
        counts = current_migration.not_final.group("model_type").count
        MIGRATABLE_MODELS.each do |migratable_model|
          if migratable_model.post_processor.present?
            value = counts[migratable_model.model_type]
            next unless value
            counts[migratable_model.model_type] = value * 2
          end
        end

        counts.values.sum + 2 # Add 2 for UserSuspender and ModelIndexer
      end
    end

    def import_mapper
      @import_mapper ||= ImportMapper.new(guid: guid)
    end

    private

    # Internal: The path to the migration archive.
    #
    # Returns a String.
    attr_reader :archive_path

    # Internal: The directory path where the migration files will be saved
    # during export, prepare, and import.
    #
    # Returns a String.
    attr_reader :migration_path

    # Internal: The path to the archive being created.
    #
    # Returns a String.
    attr_reader :archive_export_path

    # Internal: Actor using the gh-migrator tool.
    attr_reader :actor

    attr_reader :owner

    # Internal: Records to process per second. Used by per_second_throttler.
    attr_reader :per_second

    # Internal: This flag allows us to bypass any import errors by logging them and continuing import.
    attr_reader :skip_import_errors

    # Internal: This flag allows us to bypass archiving repo git data for Octoshift exports.
    attr_reader :exclude_git_data

    # Internal: This flag allows us to know this is a Octoshift Organization exports.
    attr_reader :org_metadata_only

    # Internal: This flag allows us to bypass exporting metadata outside of the repo git data.
    attr_reader :exclude_metadata

    # Internal: Find or initialize MigratableResource by source_url, optionally
    # passing a block.
    #
    # source_url - String url.
    #
    # Returns a MigratableResource.
    def migratable_resource_from_source_url(source_url, &block)
      current_migration.by_source_url(source_url, &block)
    end

    # Internal: Verify that the target url is a valid https or http URL.
    def verify_target_url!(target_url)
      return unless target_url
      unless target_url[/\A#{URI.regexp(%w[https http])}\z/]
        raise ArgumentError, "Exported to URL is not a valid URL"
      end
    end

    # Internal: Verify that the schema version in the archive matches what we expect.
    def verify_schema_version!
      unless schema_version.can_import?(archive_schema_version)
        raise UnsupportedSchemaVersion
      end
    end

    # Internal: Verify that this `gh-migrator prepare` isn't reusing a guid from an earlier attempt.
    def verify_new_guid!
      return if @reuse_guid

      if MigratableResource.where(guid: guid).any?
        raise GuidCollision, "#{guid} is already in use and cannot be used for a new import."
      end
    end

    # Internal: Set state on migratable resources.
    #
    # state                - Symbol state for MigratableResource.
    # migratable_resources - Array of MigratableResource instances.
    def set_state_on_migratable_resources(state, migratable_resources)
      ActiveRecord::Base.connected_to(role: :writing) do
        current_migration.set_state!(state, migratable_resources)
      end
    end

    def invalid_map_org?(model, target_org)
      model.is_a?(Organization) && model != target_org
    end

    def invalid_map_user?(model, target_org)
      return false unless model.is_a?(User) && model.user?
      return false if model.ghost?
      !target_org.member?(model)
    end

    def cached_url_templates
      kv_key = "migrationUrlTemplates-#{guid}"
      if GitHub::Migrator::KV.store.exists(kv_key).value { false }
        kv_results = GitHub::Migrator::KV.store.get(kv_key).value { nil }
        JSON.parse(kv_results)
      else
        DefaultUrlTemplates
      end
    end

    # Private: Determine whether or not to use the experimental exporter which
    # will allow batching exports into smaller chunks for larger customers.
    # This is highly experimental and temporary -- this code should be removed
    # once we've completed the migration for Databricks.
    #
    # repository - Repository model
    #
    # Returns an exporter klass name.
    def export_preparer_klass(repository)
      if GitHub.flipper[:octoshift_experimental_incremental_migrations].enabled?(repository)
        GitHub::Migrator::ExperimentalBatchExportPreparer
      elsif GitHub.flipper[:octoshift_databricks_issue_9713].enabled?(repository)
        GitHub::Migrator::DatabricksIssue9713ExportPreparer
      else
        GitHub::Migrator::ExportPreparer
      end
    end
  end
end
