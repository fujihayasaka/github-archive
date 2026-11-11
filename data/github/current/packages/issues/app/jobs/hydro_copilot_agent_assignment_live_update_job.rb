# typed: true
# frozen_string_literal: true

# HydroCopilotAgentAssignmentLiveUpdateJob listens for CopilotApiAgentSession events.
#
# For "issues_agent_assignment" events: fetches the AgentAssignment by task_id and notifies the source issue
# over websocket.
#
# For "issue_created" events (automations): creates an AgentAssignment record so the automation session
# becomes visible on the issue page, then notifies over websocket.
class HydroCopilotAgentAssignmentLiveUpdateJob < HydroMessageJob
  queue_as :hydro_copilot_agent_assignment_live_update
  retry_on_dirty_exit

  FEATURE_FLAG = :agent_assignment_session_live_updates
  AUTOMATION_FEATURE_FLAG = :agent_assignment_from_automation_events

  AUTOMATION_EVENT_TYPES = %w[issue_created].freeze

  sig { void }
  def perform
    return unless topic == "copilot.api.v0.CopilotApiAgentSession"

    event_type = message[:event_type]
    task_id = message[:task_id]
    return unless task_id.present?

    if event_type == "issues_agent_assignment"
      handle_live_update_agent_assignment(task_id)
    elsif AUTOMATION_EVENT_TYPES.include?(event_type)
      handle_automation_event(task_id)
    end
  end

  private

  sig { params(task_id: String).void }
  def handle_live_update_agent_assignment(task_id)
    agent_assignment = AgentAssignment.find_by(task_id:)
    return unless agent_assignment

    return unless FeatureFlag.vexi.enabled?(FEATURE_FLAG, [agent_assignment.subject_repository, agent_assignment.assigner], default: false)

    agent_assignment.notify_socket_subscribers
  end

  sig { params(task_id: String).void }
  def handle_automation_event(task_id)
    repo_id = message.dig(:repo_id, :value)
    agent_integration_id = message.dig(:agent_id, :value)
    actor_id = message.dig(:user_id, :value)
    event_identifiers = message.dig(:metadata, :event_identifiers)
    issue_id = event_identifiers&.first

    return unless repo_id && agent_integration_id && actor_id && issue_id.present?

    repository = Repository.find_by(id: repo_id)
    return unless repository

    return unless FeatureFlag.vexi.enabled?(AUTOMATION_FEATURE_FLAG, repository, default: false)

    return if AgentAssignment.exists?(task_id:, subject_repository_id: repository.id)

    agent = AgenticApp.agent_for_integration_id(agent_integration_id)
    return unless agent

    bot = Bot.find_by(id: agent.bot_id)
    return unless bot

    actor = User.find_by(id: actor_id)
    return unless actor

    ActiveRecord::Base.connected_to(role: :writing) do
      AgentAssignment.create!(
        subject_repository: repository,
        source_type: :issue,
        source_id: issue_id,
        subject_type: :issue,
        subject_id: issue_id,
        status: :pending,
        assignee: bot,
        assigner: actor,
        task_id: task_id,
      )
    end
  end
end
