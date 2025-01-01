# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class HydroIssueCloseProjectAutomationJob < MemexHydroProjectAutomation::HydroBasePipedProjectAutomationJob
  queue_as :hydro_issue_close_project_automation

  # This gets called by the base class when a new message is pulled off the
  # queue.
  #
  # `message` and a number of other attrs (like `topic`, `schema`, etc.) are
  # automatically available on the instance.
  def perform
    log_topic
    return skip_automations_disabled unless GitHub.projects_automation_enabled?
    repository_id, content_id, content_type = message_content(message)
    trigger_type = schema.end_with?("PullRequestMerge") ? :merged : :closed
    actor = User.new(id: message[:actor][:id])

    enqueue_related_workflows(repository_id, content_id, content_type, :set_field, actor, trigger_type)
  end

  # Basic conditionals to return the right content values based on whether this
  # message is connected to a pull request or issue.
  #
  # message - Hash - The original Hydro message value, with keys symbolized
  #
  # Returns Array<Integer, String> - The content id and type
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
