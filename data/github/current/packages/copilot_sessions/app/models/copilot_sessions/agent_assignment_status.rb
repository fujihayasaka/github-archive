# typed: true
# frozen_string_literal: true

module CopilotSessions
  # Single source of truth for translating a Copilot session lifecycle state into
  # an `AgentAssignment.status` value, plus the transition policy used to persist it.
  #
  # Both the live consumer (HydroSweAgentJobStatusChangeJob) and the one-time
  # backfill (BackfillAgentAssignmentStatusJob) MUST use this module so the mapping
  # stays identical. The transition POLICY differs by caller (see
  # `allowed_source_statuses`): the live consumer is permissive (a resumed session
  # may move a terminal row back to :active), while the backfill is a pending-only
  # repair that never overwrites a row a live event has already advanced.
  #
  # Related: github/planning-tracking#3131
  module AgentAssignmentStatus
    # `AgentAssignment` statuses that represent a finished session.
    #
    # NOTE: terminals are no longer globally immutable. On the LIVE path a resumed
    # session (Start event after a Finish) is allowed to move a terminal row back
    # to :active. This constant is kept for classification only. The
    # never-regress guarantees that DO still hold are: (a) the BACKFILL path only
    # writes rows still at NULL or :pending, and (b) no path ever regresses to
    # :pending.
    TERMINAL_STATUSES = T.let(%i[completed failed error].freeze, T::Array[Symbol])

    # Transition policies accepted by `allowed_source_statuses` / `apply_status!`.
    LIVE_EVENT = T.let(:live_event, Symbol)
    PENDING_BACKFILL = T.let(:pending_backfill, Symbol)

    # Hydro topics that report the end of a session.
    FINISH_TOPICS = T.let(
      %w[
        github.copilot.v0.AgentSessionFinish
        github.copilot.v0.AgentSessionFinishPullRequest
      ].freeze,
      T::Array[String]
    )

    # Maps a resolved session state to the denormalized assignment status.
    sig { params(session_state: T.nilable(CopilotSessions::SessionState)).returns(T.nilable(Symbol)) }
    def self.from_session_state(session_state)
      case session_state
      when SessionState::QUEUED
        :pending
      when SessionState::IN_PROGRESS, SessionState::IDLE, SessionState::WAITING_FOR_USER
        :active
      when SessionState::COMPLETED
        :completed
      when SessionState::FAILED, SessionState::TIMED_OUT, SessionState::CANCELLED
        :failed
      end
    end

    # Maps an inbound Hydro lifecycle event (topic + message) to an assignment status.
    # Returns nil when the event carries no actionable status.
    sig { params(topic: String, message: T::Hash[Symbol, T.untyped]).returns(T.nilable(Symbol)) }
    def self.from_hydro_event(topic, message)
      session_state =
        begin
          SessionState.from_hydro_message(topic, message)
        rescue KeyError
          # Forward-incompatible / unknown session_state string on a Finish event.
          nil
        end

      status = from_session_state(session_state) if session_state
      return status if status

      # A Finish event we couldn't map to a known lifecycle state but that reports a
      # hard error is recorded as :error rather than silently dropped.
      return :error if FINISH_TOPICS.include?(topic) && message[:error_code].present?

      nil
    end

    # Maps a raw session-state string (as returned by the Task API) to an assignment
    # status. Used by the backfill when reconciling against Mission Control.
    sig { params(status_string: T.nilable(String)).returns(T.nilable(Symbol)) }
    def self.from_status_string(status_string)
      return nil if status_string.blank?

      session_state =
        begin
          SessionState.deserialize(status_string)
        rescue KeyError
          nil
        end

      from_session_state(session_state)
    end

    # The set of current statuses from which a transition to `target` is allowed,
    # given the caller's `policy`. Used to build race-safe conditional UPDATEs.
    #
    # * `:live_event` (HydroSweAgentJobStatusChangeJob) is authoritative event
    #   truth and is permissive: a resumed session may move a terminal row back to
    #   :active. Terminal targets still use first-terminal-wins (only pending/active
    #   may advance to a terminal), and nothing returns to :pending.
    # * `:pending_backfill` (BackfillAgentAssignmentStatusJob) is best-effort repair
    #   of historical rows: it only ever writes a row whose status is STILL NULL
    #   (created before the status column existed) or :pending at write time. NULL
    #   is added as a writable source by `apply_status!`, not here. The backfill
    #   reads Mission Control at T0 and writes at T2; a NULL-or-pending CAS
    #   guarantees a concurrent live resume in that gap is never clobbered, and
    #   makes the "0 rows updated => not applicable" net hold.
    sig { params(target: Symbol, policy: Symbol).returns(T::Array[Symbol]) }
    def self.allowed_source_statuses(target, policy:)
      case policy
      when PENDING_BACKFILL
        %i[pending]
      when LIVE_EVENT
        case target
        when :pending
          %i[pending]
        when :active
          # Resume fix: a finished session that restarts may move back to :active.
          %i[pending active completed failed error]
        when :completed, :failed, :error
          # First-terminal-wins; a real resume runs terminal -> active -> terminal.
          %i[pending active]
        else
          []
        end
      else
        []
      end
    end

    sig { params(target: Symbol).returns(T::Boolean) }
    def self.terminal?(target)
      TERMINAL_STATUSES.include?(target)
    end

    # Race-safe write of `target` onto the assignment with the given id, under the
    # caller's `policy` (see `allowed_source_statuses`).
    #
    # Implemented as a single conditional UPDATE guarded by the allowed source
    # statuses, so concurrent writers (the live Hydro consumer and the backfill)
    # interleave safely: the live path applies authoritative event truth (including
    # terminal -> active resume), while the backfill only repairs rows still at
    # NULL or :pending. Returns the number of rows updated (0 when the transition
    # was not allowed from the current status).
    #
    # The target is always excluded from its own allowed sources here (one place,
    # both policies), so a duplicate event that wouldn't change the status is a
    # true no-op: no row touched, no updated_at churn, no metric.
    #
    # Callers are responsible for routing this to the writer database (e.g. via
    # `with_write`) and for any throttling.
    sig { params(assignment_id: Integer, target: Symbol, policy: Symbol).returns(Integer) }
    def self.apply_status!(assignment_id:, target:, policy:)
      target_value = AgentAssignment.statuses.fetch(target.to_s)
      allowed = allowed_source_statuses(target, policy: policy)
        .map { |status| AgentAssignment.statuses.fetch(status.to_s) }
        .reject { |value| value == target_value }
      return 0 if allowed.empty?

      # Historical rows created before the status column existed have a NULL status.
      # The backfill must repair those too, so NULL is a writable source for the
      # pending-only repair path only. The live path never treats NULL as writable.
      source_statuses = policy == PENDING_BACKFILL ? [nil, *allowed] : allowed

      AgentAssignment
        .where(id: assignment_id, status: source_statuses)
        .update_all(status: target_value, updated_at: Time.current)
    end
  end
end
