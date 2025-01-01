# typed: false
# frozen_string_literal: true

module Gist::Backup
  include GitBackups

  def backups_enabled?
    GitHub.realtime_backups_enabled?
  end

  # Perform a backup via gitbackups
  def backup_ng!(use_spokes = false)
    _run_backup_ng(false, use_spokes)
  end

  # Queue a job to run git-backup on the repository
  def async_backup(backfill = false, opts: {})
    return unless backups_enabled?
    return if backfill # this comes from the legacy sweeper

    RepositoryBackupNgJob.perform_later(id, :gist, opts)
  end
end
