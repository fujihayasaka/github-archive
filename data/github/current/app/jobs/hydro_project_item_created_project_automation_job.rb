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

    content_type = project_item.content_type
    actor = User.new(id: message[:actor][:id])

    enqueue_workflows_for_project_item(project_item, :set_field, actor, :item_added)

    sub_issues_enabled = SubIssuesFeature.enabled?(project_item.memex_project)
    project_item_has_sub_issues = project_item.content.try(:sub_issues).present?
    if sub_issues_enabled && project_item_has_sub_issues
      log("Item eligible for sub-issues workflow")
      enqueue_workflows_for_project_item(project_item, :add_project_item, actor, :sub_issues)
    else
      log(
        "Item ineligible for sub-issues workflow",
        "sub_issues.enabled" => sub_issues_enabled,
        "sub_issues.present" => project_item_has_sub_issues,
      )
    end
  end

  private def message_content(message)
    message.dig(:memex_project_item, :id)
  end

  def project_item_processable?(_project_item)
    true
  end
end
