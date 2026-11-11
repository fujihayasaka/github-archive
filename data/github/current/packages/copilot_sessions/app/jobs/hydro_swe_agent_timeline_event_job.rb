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
    elsif topic == "github.copilot.v0.AgentSessionFinishPullRequest" && CopilotSessions::SessionState.deserialize(session_state) == CopilotSessions::SessionState::FAILED
      event = "copilot_work_finished_failure"
    elsif topic == "github.copilot.v0.AgentSessionFinishPullRequest"
      event = "copilot_work_finished"
    else
      return
    end

    issue = Issue.includes(:pull_request).find_by(pull_request_id: pull_request_id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    pull_request = issue&.pull_request
    return unless issue.present? && pull_request.present?

    cca_id = ::Apps::Privileged.integration(:copilot_swe_agent)&.id
    ccr_id = ::Apps::Privileged.integration(:copilot_pull_request_reviewer)&.id
    allowed_integration_ids = [cca_id, ccr_id].compact

    # CCR doesn't need the work finished event since it posts a PR review when it's finished
    if performed_by_integration_id == ccr_id
      return unless FeatureFlag.vexi.enabled?(:copilot_code_reviews_view_session, pull_request.repository, pull_request.repository&.owner, default: false)
      return if event == "copilot_work_finished"
    end

    if FeatureFlag.vexi.enabled?(:agentic_view_session, pull_request.repository, pull_request.repository&.owner, default: false)
      # check that the integration is allowed to create events
      return unless allowed_integration?(performed_by_integration_id, pull_request)
    else
      return unless allowed_integration_ids.include?(performed_by_integration_id)
    end

    issue_event = if FeatureFlag.vexi.enabled?("copilot_swe_agent_timeline_trigger_source", actor_id, default: false)
      ActiveRecord::Base.connected_to(role: :writing) do
        IssueEvent.create(
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
        IssueEvent.create(
          issue:,
          event:,
          actor_id:,
          performed_by_integration_id:,
          source_id:,
          message: error_message,
        )
      end
    end
    unless issue_event.persisted?
      GitHub.dogstats.increment("hydro_swe_agent_timeline_event_job.issue_event.not_persisted", tags: ["event:#{event}"])
      return
    end

    pull_request.notify_socket_subscribers
  end

  def allowed_integration?(integration_id, pull_request)
    if ::Apps::Privileged.integration(:copilot_pull_request_reviewer)&.id == integration_id
      return true
    end

    agent = ::AgenticApp.agent_for_integration_id(integration_id)
    return false if agent.nil?

    true
  end
end
