# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: strict
# frozen_string_literal: true

class HydroPrConnectedProjectAutomationJob < MemexHydroProjectAutomation::HydroBasePipedProjectAutomationJob
  queue_as :hydro_pr_connected_project_automation

  TRIGGER_TYPE = :pr_connected

  sig { void }
  def perform
    log_topic
    return skip_automations_disabled unless GitHub.projects_automation_enabled?

    repository_id, content_id = message_content(message)
    return skip_no_matches unless repository_id && content_id

    actor = User.new(id: message[:actor][:id])
    feature_enabled = FeatureFlag.vexi.enabled?(:memex_linked_pr_progress_workflow, actor, default: false)
    return skip_disabled unless feature_enabled

    content_type = "Issue"
    enqueue_related_workflows(repository_id, content_id, content_type, :set_field, actor, TRIGGER_TYPE)
  end

  sig { params(message: T::Hash[Symbol, T.untyped]).returns([T.nilable(Integer), T.nilable(Integer)]) }
  private def message_content(message)
    repository_id = message.dig(:issue_repository, :id)
    issue_id = message.dig(:issue, :id)
    [repository_id, issue_id]
  end

  sig { params(_project_item: MemexProjectItem).returns(T::Boolean) }
  private def project_item_processable?(_project_item)
    true
  end
end
