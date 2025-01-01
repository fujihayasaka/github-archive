# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: strict
# frozen_string_literal: true

# This job is responsible enqueing workflow runs for auto-close when a project item's status is changed
class HydroProjectItemColumnUpdateAutomationJob < MemexHydroProjectAutomation::HydroBasePipedProjectAutomationJob
  queue_as :hydro_project_item_column_update_automation

  sig { void }
  def perform
    log_topic
    return skip_automations_disabled unless GitHub.projects_automation_enabled?
    return skip_kill_switch_enabled if FeatureFlag.vexi.enabled?(:memex_project_automation_auto_close_kill_switch, default: false)

    project_item_id = message.dig(:project_item, :id)
    actor_id = message.dig(:actor, :id)

    memex_project_item = project_item(project_item_id) if project_item_id
    actor = with_read { User.find_by(id: actor_id) } if actor_id

    return skip_missing_required_data unless memex_project_item
    return skip_missing_required_data unless actor

    enqueue_workflows_for_project_item(memex_project_item, MemexProjectWorkflowAction::CloseItemActionRunner::ACTION_TYPE, actor)
  end

  sig { params(project_item: MemexProjectItem).returns(T::Boolean) }
  private def project_item_processable?(project_item)
    project_item.memex_project.present?
  end
end
