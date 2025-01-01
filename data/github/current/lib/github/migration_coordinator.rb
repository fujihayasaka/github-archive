# typed: true
# frozen_string_literal: true

module GitHub
  # Coordinate migrations of repositories from one GitHub instance to
  # another.
  class MigrationCoordinator
    include GitHub::Migrator::DownloadHelpers
    include GitHub::Migrator::TarUtils
    include GitHub::RateLimitable
    include Migrator::MigratorHelper

    def initialize(migrator: nil)
      @migrator = migrator
    end

    attr_reader :migrator

    class RateLimitExceeded < StandardError; end

    DOWNLOAD_EVERYTHING_LIMIT = 6
    DOWNLOAD_EVERYTHING_LIMIT_TTL = 24.hours
    DOWNLOAD_EVERYTHING_MAX_REPO_SIZE = 1.gigabyte / 1.kilobyte # == 1GB, as this measure is in kilobytes

    def rate_limited?(current_user)
      return false unless GitHub.rate_limiting_enabled?
      rate_limit_increment(
        "download_everything.#{current_user.id}",
        { max_tries: DOWNLOAD_EVERYTHING_LIMIT, ttl: DOWNLOAD_EVERYTHING_LIMIT_TTL }
      ).at_limit?
    end

    def download_everything(current_user)
      warnings = []
      if rate_limited?(current_user)
        raise RateLimitExceeded
      else
        downloadable_repos = current_user.repositories.where("disk_usage < ?", DOWNLOAD_EVERYTHING_MAX_REPO_SIZE)

        if current_user.has_any_trade_restrictions?
          downloadable_repos = downloadable_repos.public_scope
          warnings.push(::TradeControls::Notices.notice_as_plaintext(:user_account_restricted))
        end

        migration = export_later \
          repos: downloadable_repos,
          owner: current_user,
          current_user: current_user,
          lock: false,
          exclude_attachments: false

        GlobalInstrumenter.instrument "user.migration_start", user: current_user
        GitHub.dogstats.increment("download_everything.start")

        big_repos = current_user.repositories.where("disk_usage >= ?", DOWNLOAD_EVERYTHING_MAX_REPO_SIZE)
        if big_repos.any?
          warnings.push("Migration started. Some repositories were too large to be included in the export. Please
            visit the Migration API to export:")
          repo_names = big_repos.pluck(:name).join(", ")
          warnings.push(repo_names)
          GitHub.dogstats.increment("download_everything.oversized_repos")
        end
      end
      warnings
    end

    # Public: Start a migration.
    def export_later(
      repos:,
      owner:,
      business: nil,
      current_user:,
      lock: false,
      exclude_metadata: false,
      exclude_git_data: false,
      exclude_attachments: false,
      exclude_releases: false,
      exclude_owner_projects: false,
      org_metadata_only: false,
      include_timestamp: false,
      use_octoshift: false,
      octoshift_migration_id: nil
    )
      migration = ::Migration.create! do |m|
        m.guid = SimpleUUID::UUID.new.to_guid
        m.owner = owner
        m.business = business
        m.creator = current_user
        m.lock_repositories = lock
        m.exclude_metadata = exclude_metadata
        m.exclude_git_data = exclude_git_data
        m.exclude_attachments = exclude_attachments
        m.exclude_releases = exclude_releases
        m.exclude_owner_projects = exclude_owner_projects
        m.org_metadata_only = org_metadata_only
        m.repositories = repos
        m.state = 0 # Set the state to :pending
      end

      if GitHub.flipper[:octoshift_create_migration_export_link].enabled?(owner)
        # TODO: Remove this once Databricks migration has been successfully completed
        # Connect the migration guid with its octoshift ID so we can
        # look them up later for batching.
        OctoshiftBatchHelper::MigrationExportLink.create(migration.guid, octoshift_migration_id.to_s) if octoshift_migration_id
      end

      queue_name = use_octoshift ? "octoshift" : "gh_migrator"

      MigrationExportToArchiveJob.set(queue: queue_name).perform_later(migration, include_timestamp: include_timestamp)

      migration
    end

    # Public: Run the export.
    def export(migration, include_timestamp: false)
      # Lock repositories if lock_repositories is true
      if migration.lock_repositories?
        migration.repositories.each(&:lock_for_migration)
      end

      exported_archive = generate_exported_archive

      begin
        exported_archive.close

        migration.record_timing(:export) do
          migrator.export migration: migration, dest: exported_archive.path
        end

        update_migratable_resources_count(migration)
        upload_archive(migration, exported_archive, include_timestamp)
      rescue GitHub::Migrator::ExportFailure => e
        create_error_log(migration, exported_archive, e)
        upload_archive(migration, exported_archive, include_timestamp)
        # re-raise exception to fail export on critical failure
        raise e
      ensure
        exported_archive.close! unless Rails.env.test?
      end
    ensure
      unless ::Migration.export_disabled_for_actor?(migration.creator)
        migration.clean_up
      end
    end

    def upload_archive(migration, exported_archive, include_timestamp)
      unless ::Migration.export_disabled_for_actor?(migration.creator)
        save_archive migration: migration, exported_archive: exported_archive.path, include_timestamp: include_timestamp
      end
    end

    # Public: Queue a mapping job
    def map_later(migration, mappings, actor)
      migration.enqueue_map!
      MapImportRecordsJob.perform_later(migration, mappings, actor)
    end

    # Public: Run the map.
    def map(migration, mappings, actor)
      migration.record_timing(:map_records) do
        migrator.map(migration: migration, mappings: mappings, actor: actor)
      end
    end

    # Public: Start to prepare an import
    def prepare_later(migration:, current_user:)
      # TODO: Ensure state and/or migration file uploaded
      PrepareImportArchiveJob.perform_later(migration, current_user)
    end

    # Public: Prepare an import
    def prepare(migration, actor)
      archive_path = download_archive(tmpdir, migration, actor)

      import_preparer = GitHub::Migrator::ImportPreparer.new(
        guid: migration.guid,
        archive_path: archive_path,
        migration_path: tmpdir,
        detect_conflicts: false,
      )

      migration.record_timing(:prepare) { import_preparer.call }

      if conflicts?(migration)
        migration.conflicts_detected!
      else
        migration.no_conflicts_detected!
      end
    end

    # Public: Queue a job to import data to GitHub from Archive
    def import_later(migration:, current_user:)
      ImportArchiveJob.perform_later(migration, current_user)
    end

    # Public: Import data to GitHub from Archive
    def import(migration, actor)
      archive_path = download_archive(tmpdir, migration, actor)

      archive_url_templates = cached_url_templates_for(migration)
      migration_source = migration_source_from_url_templates(archive_url_templates)

      migration.update!(import_migration_source: migration_source)

      archive_importer = GitHub::Migrator::ArchiveImporter.new(
        guid: migration.guid,
        archive_path: archive_path,
        migration_path: tmpdir,
        actor: actor,
        owner: migration.owner,
        migration_source: migration_source
      )

      migration.record_timing(:import) { archive_importer.call }

      update_migratable_resources_count(migration)
    end

    def conflicts?(migration)
      conflicts_detector = conflicts_detector_for(migration)
      conflicts_detector.conflicts?
    end

    def conflicts(migration, max_conflicts: nil, &block)
      conflicts_detector = conflicts_detector_for(migration, max_conflicts: max_conflicts)
      conflicts_detector.call(&block)
    end

    def unlock!(migration)
      if can_unlock?(migration)
        migration.record_timing(:unlock) do
          GitHub::Migrator::MigratedRepositoriesUnlocker.call(
            guid: migration.guid,
          ).tap { migration.unlock! }
        end
      elsif migration.failed_import?
        raise GitHub::Migrator::CannotUnlockOnFailedImport
      elsif migration.unlocked?
        raise GitHub::Migrator::CannotUnlockImportAgain
      else
        raise GitHub::Migrator::CannotUnlockImportInProgress
      end
    end

    private

    def test_environment?(migration)
      Rails.env.test? && !!migration.try(:authz_test?)
    end

    def can_unlock?(migration)
      migration.imported? || test_environment?(migration)
    end

    def tmpdir
      if @tmpdir && Dir.exist?(@tmpdir)
        @tmpdir
      else
        @tmpdir = Dir.mktmpdir("gh-migrator", migration_file_staging_path)
      end
    end

    def download_archive(target_dir, migration, actor)
      archive_path = File.join(target_dir, migration.file.name)

      migration.record_timing(:download_archive) do
        save_from_url(
          url: archive_download_url(migration, actor),
          to: archive_path
        )
      end

      archive_path
    end

    def archive_download_url(migration, actor)
      migration.file.download_url(actor: actor)
    end

    def timestamp(migration)
      migration.created_at.strftime("-%Y%m%d%H%M%S")
    end

    def save_archive(migration:, exported_archive:, include_timestamp: false)
      file = migration.build_file(
        name: "#{migration.guid}#{timestamp(migration) if include_timestamp}.tar.gz",
        size: exported_archive_size(exported_archive),
        content_type: "application/x-gzip",
        uploader_id: migration.creator_id,
        supports_multi_part_upload: large_file?(exported_archive)
      )

      valid_file, errors = valid_migration_file?(file)
      raise GitHub::Migrator::ExportFailure, "Failed to validate archive. #{errors.full_messages.join(", ")}" unless valid_file

      file.save!

      policy = file.storage_policy(actor: migration.creator)

      migration.record_timing(:upload_archive) do
        GitHub::Migrator::MigrationFileUploader.new(
          migration_file: file,
          archive_path: exported_archive,
          storage_policy: policy,
        ).call
      end

      # Alambic handles tracking state as uploaded for us, so skip this in local/enterprise mode
      file.update!(state: :uploaded)
    end

    def exported_archive_size(path)
      File.size(path)
    end

    def valid_migration_file?(file)
      # Validate normally if we're not in storage cluster mode
      return file.valid?, file.errors unless GitHub.storage_cluster_enabled?

      # Ignore storage blob validation errors
      errors = file.errors.dup
      errors = errors.reject { |error| error.attribute == :storage_blob_id }
      [errors.empty?, errors]
    end

    def large_file?(path)
      File.size(path) > ::Storage::Uploadable::MAX_ASSET_SIZE
    end

    def update_migratable_resources_count(migration)
      Migrator::MigrationReporter.record_result_for(migration)
      migration.update_column(
        :migratable_resources_count,
        migration.migratable_resources.count,
      )
    end

    def set_storage_blob?(file)
      GitHub.storage_cluster_enabled? && file.respond_to?(:storage_blob) && valid_environment_for_blob_storage?
    end

    # Checks to see if we're in development or test mode
    def local_or_test_mode?
      Rails.env.development? || Rails.env.test?
    end

    # Checks to see if we're in a valid environment for blob storage
    def valid_environment_for_blob_storage?
      local_or_test_mode? || GitHub.enterprise?
    end

    def new_oid
      SecureRandom.hex 32
    end

    def conflicts_detector_for(migration, max_conflicts: nil)
      GitHub::Migrator::ConflictsDetector.new(
        guid: migration.guid,
        organization: migration.owner,
        archive_url_templates: cached_url_templates_for(migration),
        max_conflicts: max_conflicts,
      )
    end

    def cached_url_templates_for(migration)
      kv_key = "migrationUrlTemplates-#{migration.guid}"
      if GitHub::Migrator::KV.store.exists(kv_key).value { false }
        kv_results = GitHub::Migrator::KV.store.get(kv_key).value { nil }
        url_templates = JSON.parse(kv_results)
      else
        GitHub::Migrator::DefaultUrlTemplates
      end
    end

    def generate_exported_archive
      Tempfile.new(["gh-migrator", ".tar.gz"], migration_file_staging_path)
    end

    def migration_file_staging_path
      FileUtils.mkdir_p GitHub.migration_file_staging_path unless File.exist?(GitHub.migration_file_staging_path)
      GitHub.migration_file_staging_path
    end

    def create_error_log(migration, exported_archive, error)
      migration_path = Pathname(migration_file_staging_path).join(migration.guid).to_s
      Dir.mkdir(migration_path) unless File.exist?(migration_path)

      File.open(File.join(migration_path, "error.json"), "w") do |file|
        content = {
          error: error.message,
        }
        file.write content.to_json
      end

      create_archive(migration_path, exported_archive.path)
    end
  end
end
