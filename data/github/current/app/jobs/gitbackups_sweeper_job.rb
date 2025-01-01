# typed: true
# frozen_string_literal: true

class GitbackupsSweeperJob < ApplicationJob
  queue_as :gitbackups_sweeper
  exempt_from_tenant_context_requirement

  schedule interval: 4.minutes, condition: -> { GitHub.realtime_backups_enabled? }

  BACKFILL_JOB_THRESHOLD = 1000

  def queue_length
    RepositoryBackupNgBackfillJob.queue_depth
  end

  def perform
    Failbot.push app: "gitbackups"

    # The queue can get pretty large as we give backfill the lowest
    # priority. Do not bother doing anything if we're above the threshold.
    return if queue_length > BACKFILL_JOB_THRESHOLD

    SlowQueryLogger.disabled do
      GitHub::Backups::Maintenance.run_sweeper_ng
    end
  end
end
