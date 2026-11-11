# typed: strict
# frozen_string_literal: true

# Removes AgentAssignment records that were created but never received a task_id
# from the Copilot API. These orphaned records are created as placeholders during
# the assignment flow and should be updated with a task_id within seconds. Records
# older than STALE_AFTER without a task_id indicate a failed CAPI call where the
# cleanup in the assignment flow was missed.
#
# Related: github/planning-tracking#2727
class RemoveStaleAgentAssignmentsJob < ApplicationJob
  queue_as :remove_stale_agent_assignments
  retry_on_dirty_exit
  locked_by key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC, timeout: 1.day
  schedule interval: 1.hour

  STALE_AFTER = T.let(1.day, ActiveSupport::Duration)
  BATCH_SIZE = T.let(100, Integer)

  sig { void }
  def perform
    if FeatureFlag.vexi.enabled?(:remove_stale_agent_assignments_kill_switch, default: false)
      GitHub.dogstats.increment("issues.agent_assignments.stale_cleanup", tags: ["action:skipped", "reason:kill_switch"])
      return
    end

    total_deleted = 0

    loop do
      deleted_count = AgentAssignment.throttle_with_retry(max_retry_count: 3, low_priority: true) do
        # Vitess doesn't support DELETE with LIMIT on sharded tables,
        # so we pluck IDs first then delete by ID.
        ids = AgentAssignment
          .where(task_id: nil)
          .where("created_at < ?", STALE_AFTER.ago)
          .limit(BATCH_SIZE)
          .pluck(:id)
        with_write do
          AgentAssignment.where(id: ids).delete_all
        end
      end

      total_deleted += deleted_count
      break if deleted_count < BATCH_SIZE
    end

    GitHub.dogstats.count(
      "issues.agent_assignments.stale_cleanup",
      total_deleted,
      tags: ["action:destroy", "reason:missing_task_id"]
    )
  end
end
