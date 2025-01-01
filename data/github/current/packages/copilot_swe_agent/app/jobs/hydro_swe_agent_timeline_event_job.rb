# typed: true
# frozen_string_literal: true

class HydroSweAgentTimelineEventJob < HydroMessageJob
  queue_as :hydro_swe_agent_timeline_event
  retry_on_dirty_exit

  sig { void }
  def perform
    source_id, pull_request_id, actor_id, performed_by_integration_id, session_state, trigger_source_url, trigger_source_type, error_message = message.values_at(:session_id, :pull_request_id, :initiating_user_id, :agent_id, :session_state, :event_url, :event_type, :error_message)
    if topic == "github.copilot.v0.AgentSessionStartPullRequest"
      event = "copilot_work_started"
    elsif topic == "github.copilot.v0.AgentSessionFinishPullRequest" && CopilotSweAgent::SessionState.deserialize(session_state) == CopilotSweAgent::SessionState::FAILED
      event = "copilot_work_finished_failure"
    elsif topic == "github.copilot.v0.AgentSessionFinishPullRequest"
      event = "copilot_work_finished"
    else
      return
    end
    issue = Issue.includes(:pull_request).find_by(pull_request_id: pull_request_id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    pull_request = issue&.pull_request
    return unless issue.present? && pull_request.present?

    if FeatureFlag.vexi.enabled?("copilot_swe_agent_timeline_trigger_source", actor_id, default: false)
      ActiveRecord::Base.connected_to(role: :writing) do
        IssueEvent.create!(
          issue:,
          event:,
          actor_id:,
          performed_by_integration_id:,
          source_id:,
          message: error_message,
          trigger_source_url:,
          trigger_source_type:
        )
      end
    else
      ActiveRecord::Base.connected_to(role: :writing) do
        IssueEvent.create!(
          issue:,
          event:,
          actor_id:,
          performed_by_integration_id:,
          source_id:,
          message: error_message,
        )
      end
    end
    pull_request.notify_socket_subscribers
  end
end
