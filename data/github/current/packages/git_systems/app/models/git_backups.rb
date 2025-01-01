# typed: false
# frozen_string_literal: true

# Mixin for handling git backups.
#
# Include this in a model that defines the following methods:
#
# * shard_path    - the path on the FS where the repository lives.
# * rpc           - a GitRPC object that can access the repository on the FS.
module GitBackups
  # Error thrown when we fail to delete a repository from the backups
  class DeleteError < StandardError; end

  class DeleteNotAllowedError < StandardError; end

  # Perform a backup via gitbackups
  def _run_backup_ng(wiki)
    parent_id = self.is_a?(Repository) ? self.parent_id : nil
    rpc.gitbackups_perform(wiki, parent_id)
  end

  # Have the backups been disabled by git-backup-ctl?
  # See https://github.com/github/github/blob/master/git-bin/git-backupctl for git-backupctl docs
  #
  # Historically this was used to disable repos that were corrupted by grit and even more ancient
  # bugs.  See https://github.com/github/github/issues/45518 for thread that spawned this.
  def backups_disabled_by_backup_ctl?
    !!GitHub::Backups.backup_disabled_reason_for_path(shard_path)
  end

  # The queue where the backup will be queued.
  def backup_queue
    "backup_#{backup_shard}"
  end

  # The queue where the backup backfill job will be queued.
  def backfill_queue
    "backup_backfill_#{backup_shard}"
  end

  def backup_state
    resp = GitHub::Gitbackups.client.status repository_spec
    case
    when !resp.backupEnabled
      :disabled
    when resp.lastBackup.nil?
      :unavailable
    else
      :available
    end
  end

  # Public: delete a repository from backups
  #
  # May be not allowed if a hold has been placed on the data
  #
  # Returns: nothing
  def delete_backup
    raise DeleteNotAllowedError.new if legal_hold?

    if GitHub.flipper[:gitbackups_async_delete].enabled?
      GitbackupsDeleteJob.perform_later repository_spec
    else
      res = GitHub::Gitbackups.client.delete repository_spec
      raise DeleteError.new(res) unless res == :ok || res == :not_found
    end
  end

  # Private.
  def backup_shard
    if GitHub.enterprise?
      "enterprise"
    else
      @backup_shard ||= shard_path.match(/\/data\/repositories\/(\w)/)[1] rescue nil
    end
  end
end
