# typed: strict
# frozen_string_literal: true

# One-time, bounded backfill that sets `AgentAssignment.status` for historical
# assignments that were never transitioned before status denormalization existed
# (HydroSweAgentJobStatusChangeJob). Two cohorts qualify: rows created before the
# `status` column existed (status IS NULL) and rows created after it landed but
# never advanced past the create-time default (`:pending`). Both prod creation
# sites set `status: :pending` explicitly today, so new rows are `:pending`, never
# NULL — the NULL cohort is purely pre-field history.
#
# For each candidate assignment it reconciles against the true session state in
# Mission Control (the Task API) and writes the mapped status using the SAME
# mapping as the live consumer (CopilotSessions::AgentAssignmentStatus). It uses
# the pending-only backfill policy, so it ONLY repairs rows that are still NULL or
# `:pending` at write time and never clobbers a status the live consumer has
# already set (including a resume back to `:active`). This makes it idempotent
# and safe to re-run.
#
# This is a true one-time migration built on BatchedJob: it is NOT scheduled.
# Trigger it manually once (after enabling the feature flag) via `.kickoff`, which
# snapshots an upper `max_id` bound and threads it through the continuation chain
# so the drain stays bounded to rows that existed at kickoff and terminates
# naturally when a batch returns fewer than BATCH_SIZE rows.
#
# Assignments with a nil `task_id` are intentionally skipped here — those orphans
# are swept by RemoveStaleAgentAssignmentsJob.
#
# IMPORTANT (run order): this status backfill MUST run before any concurrency
# counter recompute/backfill, otherwise a recompute would still count dead sessions
# as live and re-pin the jammed counters.
#
# Related: github/planning-tracking#3131
class BackfillAgentAssignmentStatusJob < BatchedJob
  queue_as :backfill_agent_assignment_status
  retry_on_dirty_exit

  BATCH_SIZE = 100
  METRIC = "issues.agent_assignments.status_backfill"

  # Defense-in-depth feature-flag gate. Placing this in `around_perform` (rather
  # than overriding the framework's private `perform`) means flipping the flag off
  # mid-run halts the continuation chain on the next batch.
  around_perform do |_job, block|
    if FeatureFlag.vexi.enabled?(:backfill_agent_assignment_status_enabled, default: false)
      with_read { block.call }
    else
      GitHub.dogstats.increment(METRIC, tags: ["action:skipped", "reason:disabled"])
      GitHub.logger.info("Skipping #{self.class.name}: feature flag disabled")
    end
  end

  # Historical assignments not yet reconciled: rows whose status was never set
  # (NULL, pre-column) or that are still at the create-time default (:pending),
  # and that have a task we can look up in Mission Control. `where(status: [nil, 0])`
  # generates `status IS NULL OR status = 0`, covering both cohorts.
  sig { returns(ActiveRecord::Relation) }
  def self.candidate_scope
    AgentAssignment
      .where(status: [nil, AgentAssignment.statuses.fetch("pending")])
      .where.not(task_id: nil)
  end

  # Manual one-shot entry point. Snapshot the upper id bound ONCE here so the
  # whole continuation chain stays bounded to rows that existed at kickoff and
  # this "one-time" backfill never chases rows created after it started. The
  # framework threads `**options` (max_id, dry_run) into every continuation.
  # Trigger this manually after enabling :backfill_agent_assignment_status_enabled.
  sig { params(dry_run: T::Boolean).void }
  def self.kickoff(dry_run: false)
    perform_later(max_id: candidate_scope.maximum(:id) || 0, dry_run: dry_run)
  end

  # rubocop:disable Sorbet/ForbidTUntyped -- matches BatchedJob base interface
  sig do
    params(
      args: T.untyped,
      timestamp: Time,
      offset_item_id: Integer,
      progress: Integer,
      options: T.untyped,
    ).returns(T::Array[AgentAssignment])
  end
  def next_batch(*args, timestamp: Time.now.utc, offset_item_id: 0, progress: 0, **options)
    max_id = options[:max_id].to_i
    self.class.candidate_scope
      .where("id > ? AND id <= ?", offset_item_id, max_id)
      .order(:id)
      .limit(BATCH_SIZE)
      .to_a
  end

  sig { params(batch: T::Array[AgentAssignment], args: T.untyped, options: T.untyped).void }
  def process_batch(batch, *args, **options)
    dry_run = options.fetch(:dry_run, false)
    counts = T.let(Hash.new(0), T::Hash[String, Integer])
    would_change = T.let([], T::Array[String])

    batch.each do |assignment|
      result = reconcile(assignment, dry_run: dry_run, would_change: would_change)
      key = result.to_s
      counts[key] = counts.fetch(key, 0) + 1
    end

    log_batch(counts: counts, would_change: would_change, dry_run: dry_run)
  end
  # rubocop:enable Sorbet/ForbidTUntyped

  private

  # Reconcile a single assignment against Mission Control and persist the mapped
  # status under the pending-only backfill policy. Returns a result symbol
  # (:updated / :would_update / :skipped) so the caller can tally per-batch counts;
  # per-row metrics are still emitted here.
  sig { params(assignment: AgentAssignment, dry_run: T::Boolean, would_change: T::Array[String]).returns(Symbol) }
  def reconcile(assignment, dry_run:, would_change:)
    assigner = assignment.assigner
    unless assigner
      increment("skipped", "missing_assigner")
      return :skipped
    end

    task = CopilotSessions::TaskApi::Task.fetch_by_id(
      user: assigner,
      token: nil,
      id: assignment.task_id.to_s,
      entry_point: :agent_task_for_user
    )
    unless task
      increment("skipped", "task_not_found")
      return :skipped
    end

    target = CopilotSessions::AgentAssignmentStatus.from_status_string(task.status)
    unless target
      increment("skipped", "unknown_state")
      return :skipped
    end

    # A still-queued task maps back to :pending — nothing to do, and writing it
    # would be a no-op anyway. In-progress tasks map to :active, preserving live work.
    if target == :pending
      increment("skipped", "still_pending")
      return :skipped
    end

    # Dry-run: we've already done the per-row read above; record the would-be
    # transition and skip the write entirely.
    if dry_run
      increment("would_update", target.to_s)
      would_change << "#{assignment.id}:#{assignment.status}->#{target}"
      return :would_update
    end

    updated = AgentAssignment.throttle_with_retry(max_retry_count: 3, low_priority: true) do
      with_write do
        CopilotSessions::AgentAssignmentStatus.apply_status!(
          assignment_id: assignment.id,
          target:,
          policy: CopilotSessions::AgentAssignmentStatus::PENDING_BACKFILL
        )
      end
    end

    if updated.positive?
      increment("updated", target.to_s)
      :updated
    else
      # The row was no longer NULL/:pending at write time (e.g. the live consumer
      # set it — including a resume back to :active) during the read->write gap.
      # The pending-only backfill policy refuses the write so we never clobber
      # live work.
      increment("skipped", "not_applicable")
      :skipped
    end
  rescue CopilotAPI::Error, Copilot::Errors::TokenFailureError
    increment("skipped", "capi_error")
    :skipped
  end

  sig { returns(ActiveRecord::Relation) }
  def candidate_scope
    self.class.candidate_scope
  end

  sig { params(action: String, reason: String).void }
  def increment(action, reason)
    GitHub.dogstats.increment(METRIC, tags: ["action:#{action}", "reason:#{reason}"])
  end

  # Emit a single summary line per processed batch.
  sig { params(counts: T::Hash[String, Integer], would_change: T::Array[String], dry_run: T::Boolean).void }
  def log_batch(counts:, would_change:, dry_run:)
    summary = counts.map { |action, count| "#{action}=#{count}" }.join(" ")
    message = "[BackfillAgentAssignmentStatusJob] processed batch (dry_run=#{dry_run}): #{summary}"
    message += "; would change sample (id:from->to): #{would_change.first(20).join(", ")}" if dry_run && would_change.any?
    Rails.logger.info(message)
  end
end
