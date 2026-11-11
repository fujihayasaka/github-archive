# typed: true
# frozen_string_literal: true

# HydroSweAgentAlertTimelineEventJob listens for AgentSessionStartPullRequest and
# AgentSessionFinishPullRequest events with an event_type of "alert_agent_assignment" and
# creates a RepositoryVulnerabilityAlertEvent timeline entry on the matching alert.
class HydroSweAgentAlertTimelineEventJob < HydroMessageJob
  queue_as :hydro_swe_agent_alert_timeline_event
  retry_on_dirty_exit

  resolve_tenant_context do |message|
    repository_id = message[:repository_id]
    next if repository_id.nil? || repository_id.zero?
    ::Repositories::Public.resolve_tenant(id: repository_id)
  end

  EVENT_START_TYPE = "copilot_work_started"
  EVENT_FINISH_TYPE = "copilot_work_finished"
  SWEAGENTD_ALERT_EVENT_TYPE = "alert_agent_assignment"
  METRIC_PREFIX = "hydro_swe_agent_alert_timeline_event_job"

  sig { void }
  def perform
    case topic
    when "github.copilot.v0.AgentSessionStartPullRequest"
      handle_start
    when "github.copilot.v0.AgentSessionFinishPullRequest"
      handle_finish
    else
      skip!("unsupported_topic")
    end
  end

  private

  sig { void }
  def handle_start
    session_id, initiating_user_id, event_type, event_identifiers = message.values_at(:session_id, :initiating_user_id, :event_type, :event_identifiers)

    unless event_type == SWEAGENTD_ALERT_EVENT_TYPE
      skip!("wrong_event_type")
      return
    end

    alert_id = extract_alert_id(event_identifiers)
    unless alert_id
      skip!("missing_alert_id")
      return
    end

    alert = RepositoryVulnerabilityAlert.find_by(id: alert_id)
    unless alert
      skip!("missing_alert")
      return
    end

    with_write do
      alert.events.create!(
        event: EVENT_START_TYPE,
        actor_id: initiating_user_id,
        session_id: session_id,
      )

      RepositoryDependencyUpdate.create_for_copilot(alert: alert)
    end

    GitHub.dogstats.increment("#{METRIC_PREFIX}.created.count", tags: telemetry_tags + ["event:#{EVENT_START_TYPE}"])
  end

  sig { void }
  def handle_finish
    session_id, initiating_user_id, session_state, repository_id, pull_request_id = message.values_at(:session_id, :initiating_user_id, :session_state, :repository_id, :pull_request_id)

    alert = RepositoryVulnerabilityAlert
      .where(repository_id: repository_id)
      .joins(:events)
      .where(repository_vulnerability_alert_events: { event: "copilot_work_started", session_id: session_id })
      .first

    unless alert
      skip!("missing_start_event")
      return
    end

    if session_state.nil?
      skip!("missing_session_state")
      return
    end
    begin
      deserialized_session_state = CopilotSessions::SessionState.deserialize(session_state)
    rescue ArgumentError, KeyError
      skip!("invalid_session_state")
      return
    end
    if deserialized_session_state == CopilotSessions::SessionState::FAILED
      error_rdu(alert)
      skip!("finished_failure")
      return
    end

    with_write do
      attrs = {
        event: EVENT_FINISH_TYPE,
        actor_id: initiating_user_id,
        session_id: session_id,
      }
      attrs[:pull_request_id] = pull_request_id if pull_request_id.is_a?(Integer) && pull_request_id > 0

      alert.events.create!(attrs)
    end

    complete_rdu(alert, pull_request_id)

    GitHub.dogstats.increment("#{METRIC_PREFIX}.created.count", tags: telemetry_tags + ["event:#{EVENT_FINISH_TYPE}"])
  end

  sig { params(reason: String).void }
  def skip!(reason)
    GitHub.dogstats.increment("#{METRIC_PREFIX}.skipped.count", tags: telemetry_tags + ["reason:#{reason}"])
  end

  sig { returns(T::Array[String]) }
  def telemetry_tags
    ["topic:#{topic}"]
  end

  sig { params(event_identifiers: T.untyped).returns(T.nilable(Integer)) }
  def extract_alert_id(event_identifiers)
    return nil unless event_identifiers.is_a?(Array)

    event_identifiers.each do |identifier|
      next unless identifier.is_a?(String)

      match = identifier.match(/\Aalert_id::(\d+)\z/)
      return match[1].to_i if match
    end

    nil
  end

  sig { params(alert: RepositoryVulnerabilityAlert, pull_request_id: T.untyped).void }
  def complete_rdu(alert, pull_request_id)
    rdu = alert.repository_dependency_updates.where(trigger_type: :copilot, state: :requested).first
    return unless rdu

    pr = PullRequest.find_by(id: pull_request_id)
    return unless pr

    with_write { rdu.mark_as_complete(pull_request: pr) }
  end

  sig { params(alert: RepositoryVulnerabilityAlert).void }
  def error_rdu(alert)
    rdu = alert.repository_dependency_updates.where(trigger_type: :copilot, state: :requested).first
    return unless rdu

    with_write do
      rdu.mark_as_errored(
        title: "Copilot was unable to create a fix",
        body: "Copilot encountered an error while attempting to fix this alert.",
        type: "copilot_session_failed",
      )
    end
  end
end
