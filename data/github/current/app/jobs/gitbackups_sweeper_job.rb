# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class GitbackupsSweeperJob < ApplicationJob
  queue_as :gitbackups_sweeper
  exempt_from_tenant_context_requirement

  schedule interval: 4.minutes, condition: -> { GitHub.realtime_backups_enabled? }

  BACKFILL_JOB_THRESHOLD = 1000
  TIME_TO_RUN = 3.minutes
  SLEEP_TIME = 10.seconds

  def queue_length
    RepositoryBackupNgBackfillJob.queue_depth
  end

  def perform
    Failbot.push app: "gitbackups"

    start_time = Time.now

    # The queue can get pretty large as we give backfill the lowest
    # priority. Do not bother doing anything if we're above the threshold.
    return if queue_length > BACKFILL_JOB_THRESHOLD

    # Run the loop the one time for all of them
    SlowQueryLogger.disabled do
      GitHub::Backups::Maintenance.run_sweeper_ng
    end

    # And now we step forward the repositories multiple times to try to speed
    # this up. We spend about 4s in the query and we have 4m to run. Give
    # ourselves 3m to give some space in case of slowdowns
    if GitHub.flipper[:gitbackups_sweeper_keep_running].enabled?
      deadline = start_time + TIME_TO_RUN
      loop do
        return if queue_length > BACKFILL_JOB_THRESHOLD
        return if Time.now >= deadline

        SlowQueryLogger.disabled do
          GitHub::Backups::Maintenance.run_sweeper_repositories_once
        end
        sleep(SLEEP_TIME)
      end
    end
  end
end
