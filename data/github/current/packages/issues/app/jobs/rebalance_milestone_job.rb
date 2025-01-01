# typed: true
# frozen_string_literal: true

class RebalanceMilestoneJob < ApplicationJob
  queue_as :rebalance_milestone

  retry_on_dirty_exit

  # All RebalanceMilestone jobs are locked by their milestone id.
  # No attempt will be made to enqueue a job that's already running and the
  # lock is checked before running the job.
  locked_by timeout: 1.hour, key: ->(job) {
    job.arguments[0]
  }

  def perform(milestone_id, actor_id, options = {})
    return unless milestone = Milestone.find_by(id: milestone_id)

    Failbot.push(milestone_id: milestone_id)

    GitHub.context.push(actor_id: actor_id) do
      Audit.context.push(actor_id: actor_id) do
        Milestone.throttle_writes_with_retry do
          milestone.rebalance!
        end
      end
    end
  end
end
