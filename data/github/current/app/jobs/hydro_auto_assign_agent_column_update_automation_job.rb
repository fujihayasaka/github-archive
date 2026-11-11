# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: strict
# frozen_string_literal: true

# This job is responsible for enqueuing auto-assign-agent workflow runs
# when a project item's column value is updated
class HydroAutoAssignAgentColumnUpdateAutomationJob < MemexHydroProjectAutomation::HydroBasePipedProjectAutomationJob
  queue_as :hydro_auto_assign_agent_column_update_automation

  sig { void }
  def perform
    log_topic
    return skip_automations_disabled unless GitHub.projects_automation_enabled?
    return skip_kill_switch_enabled if FeatureFlag.vexi.enabled?(:memex_autopilot_kill_switch, default: false)

    actor_id = message.dig(:actor, :id)
    actor = with_read { User.find_by(id: actor_id) } if actor_id

    return skip_missing_required_data unless actor

    project_item_id = message.dig(:project_item, :id)
    memex_project_item = project_item(project_item_id) if project_item_id

    return skip_missing_required_data unless memex_project_item
    return skip_disabled unless MemexProjectFeatureCheck.enabled?(:memex_autopilot, memex_project_item.memex_project, actor: actor)

    enqueue_workflows_for_project_item(
      memex_project_item,
      MemexProjectWorkflowAction::AssignCopilotActionRunner::ACTION_TYPE,
      actor,
      :auto_assign_agent
    )
  end

  sig { params(project_item: MemexProjectItem).returns(T::Boolean) }
  private def project_item_processable?(project_item)
    project_item.memex_project.present?
  end
end
