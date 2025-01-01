# typed: true
# frozen_string_literal: true

# This job is responsible enqueing workflow runs for auto archive when items are closed
# Eventually this will be configured in dotcom.yml for the same close events as HydroIssueCloseProjectAutomationJob
# See hydro_issue_close_project_automation entries in config/aqueduct_hydro_message_bridge/dotcom.yml
class HydroArchiveProjectItemOnCloseAutomationJob < MemexHydroProjectAutomation::HydroBasePipedProjectAutomationJob
  queue_as :hydro_archive_project_item_on_close_automation

  # This gets called by the base class when a new message is pulled off the
  # queue.
  #
  # `message` and a number of other attrs (like `topic`, `schema`, etc.) are
  # automatically available on the instance.
  def perform
    log_topic
    return skip_automations_disabled unless GitHub.projects_automation_enabled?
    repository_id, content_id, content_type = message_content(message)
    actor = User.new(id: message[:actor][:id])
    enqueue_related_workflows(repository_id, content_id, content_type, :archive_project_item, actor)
  end

  def project_item_processable?(project_item)
    project_item.memex_project.present?
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
end
