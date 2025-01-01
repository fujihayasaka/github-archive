# typed: true
# frozen_string_literal: true

class HydroIssuePrReopenedProjectAutomationJob < MemexHydroProjectAutomation::HydroBasePipedProjectAutomationJob
  queue_as :hydro_issue_pr_reopened_project_automation

  TRIGGER_TYPE = :reopened

  # Public: process a Hydro message
  #
  # Returns nothing
  def perform
    log_topic
    return skip_automations_disabled unless GitHub.projects_automation_enabled?
    repository_id, content_id, content_type = message_content(message)
    actor = User.new(id: message[:actor][:id])

    enqueue_related_workflows(repository_id, content_id, content_type, :set_field, actor, TRIGGER_TYPE)
  end

  private def message_content(message)
    repository_id = message.dig(:repository, :id)
    pull_request_id = message.dig(:pull_request, :id)
    content_id = pull_request_id || message.dig(:issue, :id)
    content_type = pull_request_id ? "PullRequest" : "Issue"
    [repository_id, content_id, content_type]
  end

  private def project_item_processable?(_project_item)
    true
  end
end
