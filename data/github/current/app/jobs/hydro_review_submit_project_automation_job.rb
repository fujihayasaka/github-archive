# typed: true
# frozen_string_literal: true

class HydroReviewSubmitProjectAutomationJob < MemexHydroProjectAutomation::HydroBasePipedProjectAutomationJob
  queue_as :hydro_review_submit_project_automation

  SKIP_REASON_NO_TRIGGER = "state did not match trigger types"

  STATE_TRIGGER_MAP = {
    CHANGES_REQUESTED: :review_changes_requested,
    APPROVED: :review_approved
  }

  # This gets called by the base class when a new message is pulled off the
  # queue.
  #
  # `message` and a number of other attrs (like `topic`, `schema`, etc.) are
  # automatically available on the instance.
  def perform
    log_topic

    return skip_automations_disabled unless GitHub.projects_automation_enabled?
    return skip(SKIP_REASON_NO_TRIGGER) unless trigger_type = trigger_type_from_state

    content_type = "PullRequest"
    repository_id = message.dig(:repository, :id)
    content_id = message.dig(:pull_request, :id)
    actor = User.new(id: message[:actor][:id])

    enqueue_related_workflows(repository_id, content_id, content_type, :set_field, actor, trigger_type)
  end

  private def trigger_type_from_state
    review_state = message.dig(:pull_request_review, :state)
    STATE_TRIGGER_MAP[review_state]
  end

  private def project_item_processable?(_project_item)
    true
  end
end
