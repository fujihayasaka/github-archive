# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class EnqueueLegacyProjectMigrationJob < ApplicationJob
  queue_as :enqueue_legacy_project_migration

  retry_on_dirty_exit

  RETRYABLE_ERRORS = [
    *Resiliency::Response::UnavailableExceptions,
    Freno::Error,
    Freno::Throttler::WaitedTooLong
  ].freeze

  discard_on(StandardError) do |_job, error|
    self.handle_exception(error)
  end

  retry_on(*RETRYABLE_ERRORS, wait: :polynomially_longer, attempts: 5) do |_job, error|
    self.handle_exception(error)
  end

  sig do
    params(
      project_id: Integer,
      actor_id: Integer,
    ).void
  end
  def perform(project_id, actor_id)
    GitHub.dogstats.increment("enqueue_project_migration.start")
    start_time = GitHub::Dogstats.monotonic_time
    Failbot.push("gh.projects.project.id": project_id)

    ActiveRecord::Base.connected_to(role: :reading) do
      return unless project = Project.find_by(id: project_id)
      return unless actor = User.find_by(id: actor_id)

      if project.project_migration.present?
        migration = T.must(project.project_migration)

        ActiveRecord::Base.connected_to(role: :writing) do

          # Migrations can be created without a spec when the number of project card exceeds a limit.
          # First, try to update the existing migration.
          if !migration.memex_project && migration.status == "pending" && actor.id == migration.requester_id
            project_migration = MemexProject::Migrator.add_spec!(migration.id)

            if project_migration.save
              MigrateLegacyProjectJob.perform_later(project_migration.id)
              handle_success(start_time)
              return
            end
          end

          # Soft delete the old memex project
          migration.memex_project&.soft_delete!(actor)
          # Delete current project migration
          migration.destroy
        end
      end

      ActiveRecord::Base.connected_to(role: :writing) do
        project_migration = MemexProject::Migrator.initialize!(actor, project)
        project_migration.save

        MigrateLegacyProjectJob.perform_later(project_migration.id)
        handle_success(start_time)
      end
    end
  end

  def handle_success(start_time)
    GitHub.dogstats.increment("enqueue_project_migration.end", tags: ["result:success"])
    GitHub.dogstats.timing_since("enqueue_project_migration.duration", start_time)
  end

  def self.handle_exception(error)
    GitHub.dogstats.increment("enqueue_project_migration.end", tags: ["result:failure", "exception:#{error.class.name.parameterize}"])
    Failbot.report(error)
  end
end
