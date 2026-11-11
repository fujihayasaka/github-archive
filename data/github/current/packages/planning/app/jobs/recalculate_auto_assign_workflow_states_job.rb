# typed: false
# frozen_string_literal: true

# Periodic safety-net that re-derives `MemexProjectAgentWorkflowState.active_sessions`
# from the source of truth in `agent_assignments`.
#
# The live hot path (`HydroAgentSessionProjectAutoAdvanceJob`) keeps the counter in
# sync via atomic decrement, but Hydro delivery loss/duplication can still cause
# drift over time. This job repairs that drift on a schedule.
#
# Per-action recompute is delegated to
# `MemexProjectAgentWorkflowState.recalculate_for_action!`, which holds a row
# lock on the state row to serialize against live increments/decrements.
#
# Uses `BatchedJob` so each invocation processes a bounded batch and
# self-enqueues a continuation until the full set is covered. This avoids
# the silent truncation of a wall-clock deadline as the dataset grows.
class RecalculateAutoAssignWorkflowStatesJob < BatchedJob
  include ActiveJob::InitiallyEnqueuedAt

  BATCH_SIZE = 100

  queue_as :recalculate_auto_assign_workflow_states
  locked_by timeout: 2.hours, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  retry_on_dirty_exit
  retry_on_recoverable_exceptions(wait: 3.seconds)

  def next_batch(*_args, offset_item_id: 0, **_options)
    if FeatureFlag.vexi.enabled?(:recalculate_auto_assign_workflow_states_kill_switch, default: false)
      GitHub.dogstats.increment(
        "memex.agent_workflow_states.recalculate",
        tags: ["action:skipped", "reason:kill_switch"]
      )
      return []
    end

    MemexProjectWorkflowAction
      .joins(:workflow)
      .where(action_type: :assign_copilot, memex_project_workflows: { trigger_type: :auto_assign_agent })
      .where("memex_project_workflow_actions.id > ?", offset_item_id)
      .order(:id)
      .limit(BATCH_SIZE)
      .to_a
  end

  def process_batch(batch, *_args, **_options)
    return if batch.empty?

    MemexProjectAgentWorkflowState.throttle do
      batch.each do |action|
        MemexProjectAgentWorkflowState.recalculate_for_action!(action)
      end
    end

    GitHub.dogstats.count(
      "memex.agent_workflow_states.recalculate",
      batch.size,
      tags: ["action:recalculated"]
    )
  end
end
