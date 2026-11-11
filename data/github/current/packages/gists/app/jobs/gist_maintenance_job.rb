# typed: true
# frozen_string_literal: true

class GistMaintenanceJob < ApplicationJob
  queue_as :gist_maintenance

  locked_by timeout: 1.hour, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  def perform(gist_id, previous_status = :scheduled)
    Failbot.push "gh.spokes.spec": "gist/#{gist_id}"

    return unless gist = Gist.find_by(id: gist_id)

    GitHub.logger.with_named_tags(
      "code.namespace" => "GistMaintenanceJob",
      "code.function" => "perform",
      "gh.job.name" => self.class.to_s,
      "gh.spokes.spec" => gist.dgit_spec
    ) do
      GitHub.logger.info(
        "Starting git maintenance",
        "gh.spokes.maintenance.status" => gist.maintenance_status,
        "gh.spokes.maintenance.elapsed" => Time.now - T.cast((gist.last_maintenance_at || gist.created_at), Time),
        "gh.spokes.maintenance.pushes" => gist.pushed_count_since_maintenance
      )
      GitHub.dogstats.distribution_time("git_maintenance.dist.perform", tags: ["type:gist"]) do
        perform!(gist, previous_status)
      ensure
        GitHub.dogstats.increment("git_maintenance", tags: ["type:gist", "result:#{gist.maintenance_status}"])
      end
    ensure
      GitHub.logger.info(
        "Exiting git maintenance",
        "gh.spokes.maintenance.status" => gist.maintenance_status
      )
    end

    nil
  end

  # Run maintenance for the given gist repository.
  def perform!(gist, previous_status = :scheduled)
    # if a backup-utils backup is in progress, delay the sync operation by
    # requeuing after a short sleep period.
    if GitHub::Enterprise.backup_in_progress?
      clear_lock
      GitHub.logger.info(
        "Gist maintenance delayed due to backup in progress",
        "code.namespace" => "GistMaintenanceJob",
        "code.function" => "perform!"
      )
      sleep 60
      with_write do
        gist.schedule_maintenance
      end
      return
    end

    with_write do
      gist.perform_maintenance(previous_status)
    end
  end
end
