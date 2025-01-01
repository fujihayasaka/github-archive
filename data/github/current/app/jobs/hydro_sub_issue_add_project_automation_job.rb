# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# This job is responsible for enqueing workflow runs for auto adding sub-issues added to parents in projects.
# See hydro_sub_issue_add_project_automation entries in config/aqueduct_hydro_message_bridge/dotcom.yml
class HydroSubIssueAddProjectAutomationJob < MemexHydroProjectAutomation::HydroBasePipedProjectAutomationJob
  queue_as :hydro_sub_issue_add_project_automation

  def perform
    log_topic
    return skip_automations_disabled unless GitHub.projects_automation_enabled?

    repository_id, parent_id, sub_issue_id, actor_id = message_content(message)
    actor = User.new(id: actor_id)

    enqueue_related_workflows(repository_id, parent_id, MemexProjectItem::ContentType::Issue.serialize, :add_project_item, actor, :sub_issues, sub_issue_id)
  end

  def project_item_processable?(project_item)
    true
  end

  private def message_content(message)
    repository_id = message.dig(:source_issue_repository, :id)
    parent_id = message.dig(:source_issue, :id)
    sub_issue_id = message.dig(:target_issue, :id)
    actor_id = message.dig(:actor, :id)

    [repository_id, parent_id, sub_issue_id, actor_id]
  end
end
