# typed: strict
# frozen_string_literal: true

class MemexProjectAgentWorkflowState < ApplicationRecord::Domain::Memexes
  DEFAULT_CONCURRENCY_LIMIT = 5

  # Non-terminal (pending/active) assignments older than this are treated as dead
  # for concurrency accounting. An auto-assign agent session never legitimately
  # occupies a slot for days; a non-terminal row this old is a session that died
  # without emitting an AgentSessionFinish event (the only terminal-marking path).
  # This is the BACKSTOP latency bound for such silent-death leaks — the live
  # decrement path still frees healthy completions instantly. It is also the MIN
  # protected lifetime for a legitimately long-lived :active session (e.g.
  # WAITING_FOR_USER), so keep it comfortably above the longest real session.
  MAX_NON_TERMINAL_ASSIGNMENT_AGE = T.let(2.days, ActiveSupport::Duration)

  belongs_to :workflow_action, class_name: "MemexProjectWorkflowAction",
    foreign_key: "memex_project_workflow_action_id", inverse_of: :agent_workflow_state

  # Atomically reserves a session slot if capacity is available.
  # Returns true if the slot was reserved, false if at capacity.
  sig { returns(T::Boolean) }
  def try_increment!
    rows_updated = ActiveRecord::Base.connected_to_many(ApplicationRecord::Memex, role: :writing) do
      self.class.where(
        memex_project_workflow_action_id: memex_project_workflow_action_id
      ).where(
        "active_sessions < concurrency_limit"
      ).update_all(
        ["active_sessions = active_sessions + 1, updated_at = ?", Time.current]
      )
    end

    rows_updated > 0
  end

  # Releases a session slot. Floors at 0 to prevent negative drift.
  sig { void }
  def decrement!
    ActiveRecord::Base.connected_to_many(ApplicationRecord::Memex, role: :writing) do
      self.class.where(
        memex_project_workflow_action_id: memex_project_workflow_action_id
      ).where(
        "active_sessions > 0"
      ).update_all(
        ["active_sessions = active_sessions - 1, updated_at = ?", Time.current]
      )
    end
  end

  # Resets active_sessions from an externally-computed count, bounded between 0
  # and concurrency_limit.
  sig { params(active_count: Integer).void }
  def recalculate!(active_count)
    update!(active_sessions: [[active_count, concurrency_limit].min, 0].max)
  end

  # Repairs active_sessions drift for a single workflow action by recomputing it
  # from the AgentAssignment source-of-truth.
  #
  # This is an eventually-consistent drift-repair primitive, NOT strict
  # concurrency control. The state row is selected FOR UPDATE so the recompute
  # serializes against the live try_increment!/decrement! update_all paths on
  # the same row, preventing this write from clobbering concurrent
  # increments/decrements. However, agent_assignments is not locked, so a brief
  # over/under-count window remains between counting and writing.
  #
  # A slot is counted as occupied when the assignment is non-terminal and has a
  # task_id. A pending assignment WITH a task_id is intentionally counted as
  # occupying a reserved slot: the slot is reserved at assignment-reserve time,
  # aligning with when try_increment! fires.
  #
  # Non-terminal assignments older than MAX_NON_TERMINAL_ASSIGNMENT_AGE are
  # excluded as presumed-dead: a session that died without emitting an
  # AgentSessionFinish event stays non-terminal forever and would otherwise pin
  # the counter. Aging is measured from created_at (assignment-reserve time), not
  # updated_at, since status churn or backfills can bump updated_at and make a
  # corpse look fresh.
  #
  # Returns the resulting active_sessions value.
  sig { params(action: MemexProjectWorkflowAction).returns(Integer) }
  def self.recalculate_for_action!(action)
    ActiveRecord::Base.connected_to(role: :writing) do
      transaction do
        state = lock.find_by(memex_project_workflow_action_id: action.id)
        unless state
          create_or_find_by!(memex_project_workflow_action_id: action.id) do |s|
            s.concurrency_limit = DEFAULT_CONCURRENCY_LIMIT
            s.active_sessions = 0
          end
          state = lock.find_by!(memex_project_workflow_action_id: action.id)
        end

        cutoff = MAX_NON_TERMINAL_ASSIGNMENT_AGE.ago
        base = AgentAssignment
          .where(source_type: :workflow_action, source_id: action.id)
          .where(status: [:pending, :active])
          .where.not(task_id: nil)
        count = base.where("created_at > ?", cutoff).count

        stale_excluded = base.where("created_at <= ?", cutoff).count
        if stale_excluded > 0
          GitHub.dogstats.count(
            "memex.agent_workflow_states.recalculate",
            stale_excluded,
            tags: ["action:stale_excluded"]
          )
        end

        state.recalculate!(count)
        state.active_sessions
      end
    end
  end
end
