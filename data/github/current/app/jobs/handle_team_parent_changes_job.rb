# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class HandleTeamParentChangesJob < ApplicationJob
  queue_as :handle_team_parent_changes
  retry_on_dirty_exit

  locked_by timeout: 1.hour, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  # Number of failures that are allowed before giving up
  # on retrying the job
  MAX_TRIES = 5

  LastErrorRetryError = Class.new(StandardError)
  retry_on LastErrorRetryError, attempts: MAX_TRIES

  # If this limit is exceeded, the job should stop processing jobs # in the loop and reenque itself
  MAX_ALLOWED_TIME = 1.minute

  attr_reader :org_id, :options

  # Algorithm
  #
  # 1. Peek a payload from the queue
  # 2. Run the recalculation transactionally
  # 3a. If recalculation succeeded
  #   - Dequeue the payload
  #   - Go to 1.
  # 3b. If recalculation failed
  #   - Wait in exponential decay
  #   - clear the lock
  #   - reenque itself passing a tries option
  #   - if we reach a limit in tries raise an error of high severity
  #
  # Unexpected situations:
  #  1. the organization could have been deleted
  #  2. the team being moved could have been deleted
  #  3. the team under which another is moved to, can be deleted
  #  4. any old ancestor could have been deleted (is a superset of 3, given that teams are removed recursiverly)
  #  5. any new ancestor could have been deleted (is a superset of 3, given that teams are removed recursiverly)
  #  6. an unexpected situation can occur :-)
  #
  def perform(org_id, options = {})
    @org_id  = org_id
    @options = options.symbolize_keys
    last_error = nil
    pending = Team::ParentChange::PendingQueue.new(org_id: org_id)
    organization = Organization.where(id: org_id).first

    if organization.nil? || organization.destroyed?
      with_write { pending.destroy }
      return
    end

    payloads_processed = 0
    started = Time.now
    elapsed = 0.0

    with_write do
      while elapsed < MAX_ALLOWED_TIME && (payload = pending.peek)
        Team::ParentChange::RecalculateAbilitiesOperation.new(payload, options).execute
        pending.dequeue
        elapsed = Time.now - started
        payloads_processed += 1
      end
    end

    GitHub.dogstats.distribution("jobs.handle_team_parent_changes.dist.duration", elapsed * 1000)
    GitHub.dogstats.distribution("jobs.handle_team_parent_changes.dist.payloads_processed", payloads_processed)
  rescue => error # rubocop:todo Lint/GenericRescue
    last_error = error
    Failbot.report(error, org_id: org_id)
  ensure
    clear_lock
    process_pending(last_error) if pending&.exist?
  end

  private

  # This job finishes when all pending jobs are being dequeued from the pending
  # queue.
  #
  # There can be two reasons why there still are pending jobs:
  #
  #  * The trickiest one can be a race condition in which just after the job has finished
  #  to process the pending moves and before the lock has been released, a user moves
  #  a team in the hierarchy, leading to a new payload, and a failed enqueue of a new job (j1),
  #  because the lock was acquired. In this case, if we don't reenqueue, there won't be any
  #  job to process the failed job, as this would have finished, and j1 was never enqueued.
  #
  #  That's why we enqueue a job again (j2). If in the race conditon j1 was able to acquire the
  #  lock, j2 will fail at acquiring the lock, and there's
  #  no problem either.
  #
  # * The second reason is an unexpected error. In this case we reenqueue the job for running it
  #  later using `ApplicationJob.retry_later` which applies exponential backoff.
  #
  def process_pending(last_error)
    return HandleTeamParentChangesJob.perform_later(org_id) unless last_error

    if executions >= MAX_TRIES
      e = Team::ParentChange::RecalculationFailedAfterSeveralRetries.new(org_id, executions, last_error)
      Failbot.report!(e, org_id: org_id, retries: executions, last_error: last_error)
      RepairAbilitiesFromUsersToAncestorTeamsJob.perform_later(org_id, {})
      GitHub.dogstats.increment("jobs.handle_team_parent_changes.abilities_operation_failed")
    end

    raise LastErrorRetryError
  end
end
