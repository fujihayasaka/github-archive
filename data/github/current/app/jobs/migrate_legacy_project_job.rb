# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class MigrateLegacyProjectJob < ApplicationJob
  # Use primary connection for writing data to memex_project_items, memex_project_column_values,
  # draft_issues, memex_project_visits, project_migrations, memex_projects tables.
  use_primaries ApplicationRecord::Memex

  queue_as :migrate_legacy_project

  retry_on_dirty_exit

  RETRYABLE_ERRORS = [
    *Resiliency::Response::UnavailableExceptions,
    Freno::Error,
    Freno::Throttler::WaitedTooLong
  ].freeze

  discard_on(StandardError) do |job, error|
    # this callback fires for all errors not covered by RETRYABLE_ERRORS
    project_migration_id = job.arguments.first
    handle_exception(project_migration_id, error)
  end

  retry_on(*RETRYABLE_ERRORS, wait: :polynomially_longer, attempts: 5) do |job, error|
    # this callback fires after all retry attempts exhausted
    project_migration_id = job.arguments.first
    handle_exception(project_migration_id, error)
  end

  def perform(project_migration_id)
    GitHub.dogstats.increment("memex_project.migration.start")

    start_time = GitHub::Dogstats.monotonic_time

    Failbot.push("gh.memex.migration.id": project_migration_id)

    MemexProject::Migrator.migrate!(project_migration_id)

    GitHub.dogstats.increment("memex_project.migration.end", tags: ["result:success"])

    GitHub.dogstats.timing_since("memex_project.migration.duration", start_time)
  end

  def self.get_tags_for_exception(exception)
    result = exception.is_a?(MemexProject::Migrator::MissingActorError) || exception.is_a?(MemexProject::Migrator::MissingProjectError) ? "invalid" : "failure"
    ["result:#{result}", "exception:#{exception.class.name.parameterize}"]
  end

  def self.handle_exception(project_migration_id, error)
    GitHub.dogstats.increment("memex_project.migration.end", tags: get_tags_for_exception(error))
    Failbot.report(error)

    migration = ProjectMigration.find_by(id: project_migration_id)

    if migration && migration.memex_project
      memex = T.must(migration.memex_project)

      migration.update!(status: "error")

      memex.notify_memex_channel(migration.as_json(dangerously_allow_all_keys: true))
    end
  end
end
