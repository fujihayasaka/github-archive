# typed: true
# frozen_string_literal: true

class HydroSweAgentActiveTasksIncrementJob < HydroMessageJob
  queue_as :hydro_swe_agent_active_tasks_increment
  retry_on_dirty_exit

  sig { void }
  def perform
    return unless topic == "github.copilot.v0.AgentSessionStartPullRequest"
    user_id = message[:initiating_user_id]
    user = User.find_by(id: user_id)
    return unless user && FeatureFlag.vexi.enabled?(:copilot_coding_agent_task_indicator, user, default: false)

    ActiveRecord::Base.connected_to(role: :writing) do
      user.settings.set!(:copilot_coding_agent_number_running_tasks, user.settings.get(:copilot_coding_agent_number_running_tasks) + 1)
    end
  end
end
