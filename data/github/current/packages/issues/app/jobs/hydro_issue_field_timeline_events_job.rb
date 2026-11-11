# typed: true
# frozen_string_literal: true

class HydroIssueFieldTimelineEventsJob < HydroMessageJob
  queue_as :hydro_issue_field_timeline_events
  retry_on_dirty_exit

  sig { void }
  def perform
    if FeatureFlag.vexi.enabled?(:issue_field_timeline_events_job_killswitch, default: false)
      return
    end

    operation = message[:operation]
    event = case operation
    when :CREATE
      "issue_field_added"
    when :DELETE
      "issue_field_removed"
    else
      "issue_field_changed"
    end

    issue_field = IssueField.find_by(id: message[:issue_field][:id])
    issue_field_name = issue_field&.name
    issue_field_value = IssueFieldValue.find_by(id: message[:issue_field_value_id])
    issue_field_type = message[:issue_field][:data_type]

    value = nil
    prev_value = nil
    issue_field_value_color = nil
    prev_field_value_color = nil
    if issue_field_type == :SINGLE_SELECT
      option = IssueFieldOption.find_by(id: message[:issue_field_option_id])
      issue_field_value_color = option&.color_id
      value = option&.name

      prev_option = IssueFieldOption.find_by(id: message[:issue_field_prev_option_id])
      prev_field_value_color = prev_option&.color_id
      prev_value = prev_option&.name
    else
      value = issue_field_value&.value
    end

    issue_id = message[:issue_id]
    issue_field_id = message[:issue_field][:id]

    ActiveRecord::Base.connected_to(role: :writing) do
      issue_event = IssueEvent.create!(
        issue_id: issue_id,
        event: event,
        actor_id: message[:actor_id],
        issue_field_id: issue_field_id,
        issue_field_name: issue_field_name,
        issue_field_data_type: IssueField.data_type_to_int(issue_field_type),
        issue_field_value: value,
        issue_field_value_color: issue_field_value_color,
        prev_issue_field_value_color: prev_field_value_color,
        prev_issue_field_value: prev_value,
      )

      # Consume any pending annotation stored by the API handler.
      # Only applies to field add/change operations where issue_field_id is present.
      # No feature flag check here — the API handler already gates storage.
      if issue_field_id.present?
        begin
          repository_id = Issue.where(id: issue_id).pick(:repository_id)
          if repository_id
            Issues::EventAnnotation.consume_pending(
              repository_id: repository_id,
              issue_id: issue_id,
              kind: Issues::EventAnnotation::KIND_FIELD,
              target_id: issue_field_id,
              issue_event_id: issue_event.id,
            )
          end
        rescue => e
          GitHub.logger.error("issues.field_event.rationale_annotation_failed", {
            "code.namespace" => "HydroIssueFieldTimelineEventsJob",
            "issue_id" => issue_id,
            "issue_event_id" => issue_event.id,
            "error" => e.message,
          })
        end
      end
    end
  end
end
