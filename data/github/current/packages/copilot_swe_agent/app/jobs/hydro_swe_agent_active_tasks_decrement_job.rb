# typed: true
# frozen_string_literal: true

class HydroSweAgentActiveTasksDecrementJob < HydroMessageJob
  queue_as :hydro_swe_agent_active_tasks_decrement
  retry_on_dirty_exit

  sig { void }
  def perform
    return unless topic == "github.copilot.v0.AgentSessionFinishPullRequest"
    user_id = message[:initiating_user_id]
    user = User.find_by(id: user_id)
    return unless user

    ActiveRecord::Base.connected_to(role: :writing) do
      currently_running_tasks = user.settings.get(:copilot_coding_agent_number_running_tasks)
      new_number_tasks = [currently_running_tasks - 1, 0].max
      user.settings.set!(:copilot_coding_agent_number_running_tasks, new_number_tasks)
      user.settings.set!(:copilot_coding_agent_task_last_completed_at, Time.current)
    end
  end
end
