# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class HydroProjectItemCreatedProjectAutomationJob < MemexHydroProjectAutomation::HydroBasePipedProjectAutomationJob
  queue_as :hydro_project_item_created_project_automation

  def perform
    log_topic
    return skip_automations_disabled unless GitHub.projects_automation_enabled?
    memex_project_item_id = message_content(message)
    project_item = project_item(memex_project_item_id)
    return skip_no_matches if project_item.nil?

    actor = User.new(id: message[:actor][:id])

    trigger_action_pairs_by_item = evaluate_workflows_for_added_items([project_item], actor)
    trigger_action_pairs_by_item.each do |item, trigger_action_pairs|
      trigger_action_pairs.each do |trigger_type, action_type|
        enqueue_workflows_for_project_item(item, action_type, actor, trigger_type)
      end
    end
  end

  private def message_content(message)
    message.dig(:memex_project_item, :id)
  end

  def project_item_processable?(_project_item)
    true
  end
end
