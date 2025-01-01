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
    return skip_kill_switch_enabled if GitHub.flipper[:memex_project_automation_auto_close_kill_switch].enabled?

    value, project_item_id, project_column_id, actor_id = message_content(message)
    memex_project_item = project_item(project_item_id)
    actor = with_read { User.find_by(id: actor_id) }

    return skip_missing_required_data unless memex_project_item
    return skip_missing_required_data unless actor

    enqueue_workflows_for_project_item(memex_project_item, MemexProjectWorkflowAction::CloseItemActionRunner::ACTION_TYPE, actor)
  end

  sig { params(project_item: MemexProjectItem).returns(T::Boolean) }
  private def project_item_processable?(project_item)
    project_item.memex_project.present?
  end

  # Extracts relevant info from the hydro message
  #
  # message - Hash - The original Hydro message value, with keys symbolized
  #
  # Returns Array<String, Integer, Integer, Integer> - The new column value, memex project item,
  # project column id, and actor id
  sig { params(message: T::Hash[Symbol, T.untyped]).returns([String, Integer, Integer, Integer]) }
  private def message_content(message)
    value = message[:value]

    # handle messages from github.memex.v0.MemexProjectItemMove schema that have an array of column update records
    if !value
      value = message.dig(:project_column_value_records).first.dig(:value)
    end

    project_item_id = message.dig(:project_item, :id)

    # handle messages from github.memex.v0.MemexProjectItemMove schema that have an array of column update records
    if message.dig(:project_column).nil?
      project_column_id = message.dig(:project_column_value_records).first.dig(:memex_project_column_id)
    else
      project_column_id = message.dig(:project_column, :id)
    end
    actor_id = message.dig(:actor, :id)

    [value, project_item_id, project_column_id, actor_id]
  end
end
