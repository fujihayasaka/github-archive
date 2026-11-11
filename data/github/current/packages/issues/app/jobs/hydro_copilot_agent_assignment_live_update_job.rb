# typed: true
# frozen_string_literal: true

# HydroCopilotAgentAssignmentLiveUpdateJob listens for CopilotApiAgentSession events with an event_type of
# "issues_agent_assignment", fetches the AgentAssignment by task_id, and notifies the source issue over websocket.
class HydroCopilotAgentAssignmentLiveUpdateJob < HydroMessageJob
  queue_as :hydro_copilot_agent_assignment_live_update
  retry_on_dirty_exit

  FEATURE_FLAG = :agent_assignment_session_live_updates

  sig { void }
  def perform
    return unless topic == "copilot.api.v0.CopilotApiAgentSession"

    event_type = message[:event_type]
    return unless event_type == "issues_agent_assignment"

    task_id = message[:task_id]
    return unless task_id.present?

    agent_assignment = AgentAssignment.find_by(task_id:)
    return unless agent_assignment

    return unless FeatureFlag.vexi.enabled?(FEATURE_FLAG, [agent_assignment.source_repository, agent_assignment.assigner], default: false)

    agent_assignment.notify_socket_subscribers
  end
end
