# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class MigrationExportToArchiveJob < ApplicationJob
  queue_as :gh_migrator

  discard_on StandardError do |job, error|
    job.fail_migration_and_raise(error)
  end

  MAX_ATTEMPTS = 5

  RETRYABLE_ERRORS = [
  GitHub::Migrator::EmptyMigration,
    ActiveRecord::Deadlocked,
    ActiveRecord::QueryCanceled,
    ActiveRecord::ConnectionNotEstablished,
    ActiveRecord::NoDatabaseError,
    ActiveRecord::StatementInvalid,
    Aqueduct::Worker::JobKilled,
    Faraday::TimeoutError,
    GitRPC::Timeout,
    ActiveRecord::ConnectionFailed,
    WaitForReplication::DataUnavailable
  ].freeze

  retry_on Freno::Throttler::Error

  retry_on *RETRYABLE_ERRORS, wait: :polynomially_longer, attempts: MAX_ATTEMPTS do |job, error|
    job.fail_migration_and_raise(error)
  end

  # shadow_migration_params: { enabled: boolean, original_migration_id: integer }
  def perform(migration, include_timestamp: false, export_batch_enabled: false, shadow_migration_params: nil)
    is_shadow = shadow_migration_params&.dig(:enabled) || false

    # Set failbot context
    Failbot.push("gh.migration_tools.migration.id" => migration.id)
    if is_shadow
      Failbot.push("gh.migration_tools.shadow_export" => true)
      Failbot.push("gh.migration_tools.original_migration.id" => shadow_migration_params[:original_migration_id])
    end

    # Set migration state to :exporting
    with_write { migration.exporting! }

    GitHub::Timer.timeout(GitHub.max_gh_migrator_export_time, GitHub::Migrator::TimeoutError) do
      with_write { GitHub.migrator.export(migration, include_timestamp: include_timestamp, export_batch_enabled: export_batch_enabled) }
    end

    # Set migration state to :exported
    with_write do
      if ::Migration.export_disabled_for_actor?(migration.creator)
        ::Migration.enable_export_for_actor(migration.creator)
      else
        migration.exported!
        send_completion_metrics!("migrator.export.success", shadow: is_shadow)
        send_file_size_metrics!(true, shadow: is_shadow)
        send_timing_metrics!("migration.export.end_to_end_duration", started_at: migration.created_at, succeeded: true, shadow: is_shadow)
      end
    end

    # Queue shadow export job after successful legacy export to compare performance
    if !export_batch_enabled && FeatureFlag.vexi.enabled?(:import_export_exporter_v2_shadow, migration.owner, default: false)
      enqueue_shadow_export(migration)
    end
    # Send shadow comparison metrics if this is a shadow run
    if is_shadow
      send_shadow_comparison_metrics!(
        migration: migration,
        original_migration_id: shadow_migration_params[:original_migration_id],
        succeeded: true
      )
    end
  rescue Aqueduct::Worker::JobKilled => error
    tags = ["migration_guid:#{migration.guid}"]
    GitHub.dogstats.increment("migrator.export.job_killed", tags: tags)
    GitHub.logger.error("Detected dirty exit, re-raising for retry",
      {
        :exception => error,
        "code.function" => __method__,
        "code.namespace" => "MigrationExportToArchiveJob",
        "gh.migration_tools.migration.guid" => migration.guid
      }
    )

    # Send shadow failure metrics if this is a shadow run
    if is_shadow
      send_shadow_comparison_metrics!(
        migration: migration,
        original_migration_id: shadow_migration_params[:original_migration_id],
        succeeded: false,
        error: error
      )
    end
    raise
  rescue StandardError => error
    # Send shadow failure metrics if this is a shadow run
    if is_shadow
      send_shadow_comparison_metrics!(
        migration: migration,
        original_migration_id: shadow_migration_params[:original_migration_id],
        succeeded: false,
        error: error
      )
    end
    raise
  end

  def fail_migration_and_raise(error)
    migration = self.arguments.first
    # ActiveJob serializes keyword arguments as the last Hash in arguments array
    kwargs = self.arguments.last if self.arguments.last.is_a?(Hash)
    shadow_migration_params = kwargs&.dig(:shadow_migration_params)
    is_shadow = shadow_migration_params&.dig(:enabled) || false

    with_write { migration.failed! }

    send_completion_metrics!("migrator.export.failure", shadow: is_shadow)
    send_file_size_metrics!(false, shadow: is_shadow)
    send_timing_metrics!("migration.export.end_to_end_duration", started_at: migration.created_at, succeeded: false, shadow: is_shadow)

    # Only report to Failbot for non-shadow runs
    unless is_shadow
      Failbot.report!(error)
    end

    raise error
  end

  private

  def enqueue_shadow_export(original_migration)
    # Create a shadow migration to run with batched export enabled
    shadow_migration = create_shadow_migration(original_migration)

    MigrationExportToArchiveJob
      .set(queue: :exporter_batch_with_storage)
      .perform_later(
        shadow_migration,
        include_timestamp: false,
        export_batch_enabled: true,
        shadow_migration_params: { enabled: true, original_migration_id: original_migration.id }
      )

    GitHub.logger.info("Shadow migration created and enqueued",
      {
        "code.function" => __method__,
        "code.namespace" => "MigrationExportToArchiveJob",
        "gh.migration_tools.original_migration.id" => original_migration.id,
        "gh.migration_tools.original_migration.guid" => original_migration.guid,
        "gh.migration_tools.shadow_migration.id" => shadow_migration.id,
        "gh.migration_tools.shadow_migration.guid" => shadow_migration.guid
      }
    )
  rescue StandardError => error
    # Don't fail the main export if shadow enqueue fails
    GitHub.logger.warn("Failed to enqueue shadow export",
      {
        :exception => error,
        "code.function" => __method__,
        "code.namespace" => "MigrationExportToArchiveJob",
        "gh.migration_tools.migration.guid" => original_migration.guid
      }
    )
    GitHub.dogstats.increment("migrator.shadow_export.enqueue_failure", tags: ["original_guid:#{original_migration.guid}"])
  end

  def create_shadow_migration(original_migration)
    with_write do
      Migration.create! do |m|
        m.guid = SimpleUUID::UUID.new.to_guid
        m.owner = original_migration.owner
        m.business = original_migration.business
        m.creator = original_migration.creator
        m.lock_repositories = false
        m.exclude_metadata = original_migration.exclude_metadata
        m.exclude_git_data = original_migration.exclude_git_data
        m.exclude_attachments = original_migration.exclude_attachments
        m.exclude_releases = original_migration.exclude_releases
        m.exclude_owner_projects = original_migration.exclude_owner_projects
        m.org_metadata_only = original_migration.org_metadata_only
        m.repositories = original_migration.repositories
        m.state = Migration.state_value(:pending) # Set the state to :pending
      end
    end
  end

  def send_shadow_comparison_metrics!(migration:, original_migration_id:, succeeded:, error: nil)
    original_migration = Migration.find_by(id: original_migration_id)
    return unless original_migration

    tags = [
      "queue_name:#{queue_name}",
      "succeeded:#{succeeded}"
    ]

    # Duration comparison using created_at to updated_at for both migrations
    # This measures total time from migration creation to completion
    if migration.created_at.present? && migration.updated_at.present? &&
       original_migration.created_at.present? && original_migration.updated_at.present?
      shadow_duration_ms = (migration.updated_at - migration.created_at) * 1000
      original_duration_ms = (original_migration.updated_at - original_migration.created_at) * 1000

      GitHub.dogstats.timing("migrator.shadow_export.duration", shadow_duration_ms, tags: tags)
      GitHub.dogstats.timing("migrator.shadow_export.original_duration", original_duration_ms, tags: tags)

      # Duration difference (negative means shadow was faster)
      duration_diff_ms = shadow_duration_ms - original_duration_ms
      GitHub.dogstats.timing("migrator.shadow_export.duration_diff", duration_diff_ms, tags: tags)

      # Speedup ratio (> 1 means shadow was faster)
      if shadow_duration_ms > 0
        speedup_ratio = original_duration_ms.to_f / shadow_duration_ms
        GitHub.dogstats.gauge("migrator.shadow_export.speedup_ratio", speedup_ratio, tags: tags)
      end
    end

    # File size comparison
    shadow_file_size = migration.file&.size || 0
    original_file_size = original_migration.file&.size || 0

    GitHub.dogstats.gauge("migrator.shadow_export.file_size", shadow_file_size, tags: tags)
    GitHub.dogstats.gauge("migrator.shadow_export.original_file_size", original_file_size, tags: tags)

    # File size difference
    file_size_diff = shadow_file_size - original_file_size
    GitHub.dogstats.gauge("migrator.shadow_export.file_size_diff", file_size_diff, tags: tags)

    # Model count comparison
    # Original uses MigratableResources, shadow uses MigrationExportBatch with serialization type
    original_resources_count = count_migratable_resources(original_migration)
    shadow_resources_count = count_serialization_batch_model_ids(migration)

    GitHub.dogstats.gauge("migrator.shadow_export.resources_count", shadow_resources_count, tags: tags)
    GitHub.dogstats.gauge("migrator.shadow_export.original_resources_count", original_resources_count, tags: tags)

    # Resource count difference as percentage of original
    if original_resources_count > 0
      resources_diff_percentage = ((shadow_resources_count - original_resources_count).to_f / original_resources_count) * 100
      GitHub.dogstats.gauge("migrator.shadow_export.resources_count_diff_percentage", resources_diff_percentage, tags: tags)
    end

    # Success/failure counter
    GitHub.dogstats.increment("migrator.shadow_export.completed", tags: tags)

    if error
      GitHub.dogstats.increment("migrator.shadow_export.failure", tags: tags + ["error_class:#{error.class.name}"])
      GitHub.logger.warn("Shadow export failed",
        {
          :exception => error,
          "code.function" => __method__,
          "code.namespace" => "MigrationExportToArchiveJob",
          "gh.migration_tools.original_migration.guid" => original_migration.guid
        }
      )
    end
  end

  # Count migratable resources for original migration by model types
  def count_migratable_resources(migration)
    model_types = GitHub::Migrator::MigratableModels::MIGRATABLE_MODELS.map(&:model_type)
    MigratableResource.where(guid: migration.guid, model_type: model_types).count
  end

  # Count model_ids from serialization batches for shadow migration
  def count_serialization_batch_model_ids(migration)
    migration.migration_export_batches
      .where(type: :serialization)
      .pluck(:model_ids)
      .sum { |ids| ids&.size || 0 }
  end

  def send_completion_metrics!(metric, shadow: false)
    migration_guid = self.arguments.first&.guid
    GitHub.dogstats.increment(metric, tags: ["guid:#{migration_guid}", "queue_name:#{queue_name}", "shadow:#{shadow}"])
  end

  def send_file_size_metrics!(export_succeeded, shadow: false)
    migration_guid = self.arguments.first&.guid
    migration_file_size = self.arguments.first&.file&.size.present? ? self.arguments.first&.file.size : 0
    GitHub.dogstats.gauge(
      "migration.export.file.size",
      migration_file_size,
      tags: [
        "guid:#{migration_guid}",
        "export_succeeded:#{export_succeeded}",
        "queue_name:#{queue_name}",
        "shadow:#{shadow}"
      ]
    )
  end

  def send_timing_metrics!(metric, started_at:, succeeded:, shadow: false)
    elapsed_time_in_ms = GitHub::Dogstats.duration(started_at)
    GitHub.dogstats.timing(metric, elapsed_time_in_ms, tags: ["succeeded:#{succeeded}", "shadow:#{shadow}"])
  end
end
