# typed: false
# frozen_string_literal: true

class WikiMaintenanceJob < ApplicationJob
  queue_as :wiki_maintenance

  locked_by timeout: 1.hour, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  def perform(wiki_id)
    Failbot.push "gh.wiki.id": wiki_id

    return unless wiki = RepositoryWiki.find_by_id(wiki_id)

    Failbot.push "gh.spokes.spec": wiki.dgit_spec

    GitHub.logger.with_named_tags(
      "code.namespace" => self.class.name,
      "code.function" => __method__,
      "gh.spokes.spec" => wiki.dgit_spec
    ) do
      GitHub.logger.info(
        "Starting git maintenance",
        "gh.spokes.maintenance.status" => wiki.maintenance_status,
        "gh.spokes.maintenance.elapsed" => Time.now - (wiki.last_maintenance_at || wiki.created_at),
        "gh.spokes.maintenance.pushes" => wiki.pushed_count_since_maintenance || 0
      )

      GitHub.dogstats.distribution_time("git_maintenance.dist.perform", tags: ["type:wiki"]) do
        perform! wiki
      ensure
        GitHub.dogstats.increment("git_maintenance", tags: ["type:wiki", "result:#{wiki.maintenance_status}"])
      end
    ensure
      GitHub.logger.info(
        "Exiting git maintenance",
        "code.function" => "exit",
        "gh.spokes.maintenance.status" => wiki.maintenance_status
      )
    end

    nil
  end

  # Run maintenance for the given wiki repository.
  def perform!(wiki)
    # if a backup-utils backup is in progress, delay the sync operation by
    # requeuing after a short sleep period.
    if GitHub::Enterprise.backup_in_progress?
      clear_lock
      GitHub.logger.info(
        "Wiki maintenance delayed due to backup in progress",
        "code.namespace" => self.class.name,
        "code.function" => __method__,
      )
      sleep 60
      with_write { wiki.schedule_maintenance }
      return
    end

    with_write { wiki.perform_maintenance }
  end
end
