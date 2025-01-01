# typed: false
# frozen_string_literal: true

module Repository::Backup
  include GitBackups

  def backups_enabled?
    GitHub.realtime_backups_enabled?
  end

  # Perform a backup via gitbackups
  def backup_ng!(use_spokes = false)
    if backups_enabled? && exists_on_disk?
      _run_backup_ng(false, use_spokes)
    end
  end

  # Queue a job to run git-backup on the repository
  def async_backup(backfill = false, opts: {})
    return unless backups_enabled?
    return if backfill # this comes from the legacy sweeper

    async_backup_delayed(2.minutes, opts: opts.merge(delay: "low"))
  end

  # Queue a delayed job to back up the repository. Use this when updating our
  # own book-keeping branches.
  #
  # Legacy backups are still enqueued immediately.
  def async_backup_delayed(delay = 10.minutes, opts: {})
    return unless backups_enabled?

    opts[:delay] ||= "high"

    if GitHub.flipper[:gitbackups_wait_increase].enabled?
      if opts[:delay] == "high"
        # "high" delay (is the default if delay is not set; 10 min without feature flag)
        delay = 60.minutes
      else
        # "low" delay (is always 2 min as defined in `async_backup` without feature flag)
        delay = 10.minutes
      end
    end
    RepositoryBackupNgJob.set(wait: delay).perform_later(id, :repository, opts)
  end

  # Perform a backup via gitbackups
  def backup_wiki_ng!(use_spokes = false)
    if backups_enabled? && unsullied_wiki && unsullied_wiki.exist?
      _run_backup_ng(true, use_spokes)
    end
  end

  # Queue a job to run git-backup-wiki on the repository
  def async_backup_wiki(opts: {})
    return unless backups_enabled?
    return unless RepositoryWiki.where(repository: self).exists?

    RepositoryBackupNgJob.perform_later(id, :wiki, opts)
  end
end
