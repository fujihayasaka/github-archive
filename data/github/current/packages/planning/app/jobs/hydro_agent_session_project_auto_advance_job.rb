# typed: true
# frozen_string_literal: true

# Listens for agent session completion events, advances completed items to a configured destination status,
# and decrements the concurrency counter on the workflow action's MemexProjectAgentWorkflowState.
class HydroAgentSessionProjectAutoAdvanceJob < HydroMessageJob
  queue_as :hydro_agent_session_project_auto_advance
  retry_on_dirty_exit

  ALLOWED_TOPIC = "github.copilot.v0.AgentSessionFinish"
  METRIC_PREFIX = "hydro_agent_session_project_auto_advance_job"

  sig { void }
  def perform
    unless topic == ALLOWED_TOPIC
      skip!("unsupported_topic")
      return
    end

    task_id = message[:task_id]
    unless task_id.present?
      skip!("missing_task_id")
      return
    end

    agent_assignment = find_agent_assignment(task_id)
    unless agent_assignment
      skip!("no_assignment")
      return
    end

    mark_assignment_terminal!(agent_assignment)

    unless agent_assignment.source_type == "workflow_action"
      skip!("non_workflow_action_source")
      return
    end

    workflow_action = find_workflow_action_for_assignment(agent_assignment)
    unless workflow_action
      skip!("missing_workflow_action")
      return
    end

    if completed_session?
      begin
        advance_project_item_to_destination_status(workflow_action, agent_assignment)
      rescue => e
        # The board advancement is best-effort: it must not gate the concurrency-slot release below.
        # If it raises, the assignment is already terminal (removed from the source-of-truth count), so
        # skipping the decrement would leak a slot and drift active_sessions upward. Report and continue.
        Failbot.report(e, app: "memex-autopilot", context: {
          method: "advance_project_item_to_destination_status",
          task_id: task_id,
          workflow_action_id: workflow_action.id,
        })
        GitHub.dogstats.increment("#{METRIC_PREFIX}.advance_failed.count", tags: telemetry_tags)
      end
    end

    state = workflow_action.agent_workflow_state
    unless state
      skip!("missing_workflow_state")
      return
    end

    ActiveRecord::Base.connected_to(role: :writing) do
      state.decrement!
    end

    GitHub.logger.info(
      "HydroAgentSessionProjectAutoAdvanceJob: decremented concurrency",
      task_id: task_id,
      workflow_action_id: workflow_action.id
    )
  end

  private

  sig { params(reason: String).void }
  def skip!(reason)
    GitHub.dogstats.increment("#{METRIC_PREFIX}.skipped.count", tags: telemetry_tags + ["reason:#{reason}"])
  end

  sig { returns(T::Array[String]) }
  def telemetry_tags
    ["topic:#{topic}"]
  end

  sig { params(task_id: String).returns(T.nilable(AgentAssignment)) }
  def find_agent_assignment(task_id)
    AgentAssignment.find_by(task_id: task_id)
  end

  sig { params(agent_assignment: AgentAssignment).void }
  def mark_assignment_terminal!(agent_assignment)
    session_state = message[:session_state]
    new_status = case session_state
    when "completed" then :completed
    when "failed", "stopped" then :failed
    else :completed
    end

    ActiveRecord::Base.connected_to(role: :writing) do
      agent_assignment.update!(status: new_status)
    end
  end

  sig { params(agent_assignment: AgentAssignment).returns(T.nilable(MemexProjectWorkflowAction)) }
  def find_workflow_action_for_assignment(agent_assignment)
    MemexProjectWorkflowAction.find_by(id: agent_assignment.source_id)
  end

  sig { returns(T::Boolean) }
  def completed_session?
    message[:session_state] == "completed"
  end

  sig { params(workflow_action: MemexProjectWorkflowAction, agent_assignment: AgentAssignment).void }
  def advance_project_item_to_destination_status(workflow_action, agent_assignment)
    destination_field_option_id = workflow_action.arguments["destinationFieldOptionId"]
    return unless destination_field_option_id.present?
    return unless agent_assignment.subject_type == "issue"

    project = workflow_action.memex_project
    return unless project

    status_column = project.status_column
    return unless status_column&.single_select_option(destination_field_option_id)

    project_item = project.memex_project_items.find_by(content_type: Issue.name, content_id: agent_assignment.subject_id)
    return unless project_item

    bot = Apps::Privileged::MemexAutomation.bot
    GitHub.context.push({ actor_id: bot.id }) do
      ActiveRecord::Base.connected_to(role: :writing) do
        project_item.set_column_value(status_column, destination_field_option_id, bot, skip_elasticsearch_updates: false)
      end
    end
  end
end
