# typed: true
# frozen_string_literal: true

class HydroIssueTypeTimelineEventsJob < HydroMessageJob
  queue_as :hydro_issue_type_timeline_events
  retry_on_dirty_exit

  sig { void }
  def perform
    if FeatureFlag.vexi.enabled_or_raise?(:issue_type_timeline_events_job_killswitch) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      return
    end

    action = message[:action]
    issue_id = message.dig(:issue, :id_value)
    actor_id = message.dig(:actor, :id)
    issue_type = message[:issue_type]
    prev_issue_type = message[:prev_issue_type]

    # issue_type_added
    #   prev_* fields will be blank.
    # issue_type_removed
    #   prev_* fields will be populated.
    # issue_type_changed
    #   both prev_* prefixed and non-prefixed fields will be populated.
    if action == "issue.typed"
      event = prev_issue_type.present? ? "issue_type_changed" : "issue_type_added"
      issue_type_id = issue_type[:id]
      issue_type_name = issue_type[:name]
      issue_type_color = issue_type[:color].downcase
      prev_issue_type_id = prev_issue_type&.dig(:id)
      prev_issue_type_name = prev_issue_type&.dig(:name)
      prev_issue_type_color = prev_issue_type&.dig(:color)&.downcase
    else
      event = "issue_type_removed"
      prev_issue_type_id = issue_type[:id]
      prev_issue_type_name = issue_type[:name]
      prev_issue_type_color = issue_type[:color].downcase
    end

    ActiveRecord::Base.connected_to(role: :writing) do
      issue_event = IssueEvent.create!(
        issue_id:,
        event:,
        actor_id:,
        issue_type_id:,
        issue_type_name:,
        issue_type_color:,
        prev_issue_type_id:,
        prev_issue_type_name:,
        prev_issue_type_color:,
      )

      # Consume any pending annotation stored by the API handler.
      # Only applies to "typed" actions (add/change) where issue_type_id is present.
      # No feature flag check here — the API handler already gates storage.
      if issue_type_id.present?
        begin
          repository_id = Issue.where(id: issue_id).pick(:repository_id)
          if repository_id
            Issues::EventAnnotation.consume_pending(
              repository_id: repository_id,
              issue_id: issue_id,
              kind: Issues::EventAnnotation::KIND_TYPE,
              target_id: issue_type_id,
              issue_event_id: issue_event.id,
            )
          end
        rescue => e
          GitHub.logger.error("issues.type_event.rationale_annotation_failed", {
            "code.namespace" => "HydroIssueTypeTimelineEventsJob",
            "issue_id" => issue_id,
            "issue_event_id" => issue_event.id,
            "error" => e.message,
          })
        end
      end
    end
  end
end
