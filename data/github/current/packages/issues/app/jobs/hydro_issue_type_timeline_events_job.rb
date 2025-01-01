# typed: true
# frozen_string_literal: true

class HydroIssueTypeTimelineEventsJob < HydroMessageJob

  queue_as :hydro_issue_type_timeline_events
  retry_on_dirty_exit

  sig { void }
  def perform
    if GitHub::flipper[:issue_type_timeline_events_job_killswitch].enabled?
      return
    end

    action = message[:action]
    issue_id = message.dig(:issue, :id)
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
      issue_type_private = issue_type[:private] || false
      prev_issue_type_id = prev_issue_type&.dig(:id)
      prev_issue_type_name = prev_issue_type&.dig(:name)
      prev_issue_type_color = prev_issue_type&.dig(:color)&.downcase
      prev_issue_type_private = prev_issue_type&.dig(:private) || false
    else
      event = "issue_type_removed"
      issue_type_private = false
      prev_issue_type_id = issue_type[:id]
      prev_issue_type_name = issue_type[:name]
      prev_issue_type_color = issue_type[:color].downcase
      prev_issue_type_private = issue_type[:private] || false
    end

    # We are deprecating private issue types, and want to stop creating events for them
    if issue_type_private || prev_issue_type_private
      return unless event == "issue_type_changed"

      return if issue_type_private && prev_issue_type_private

      # If we're changing to a non-private issue type, treat the event like an "add"
      if prev_issue_type_private
        event = "issue_type_added"
        prev_issue_type_id = nil
        prev_issue_type_name = nil
        prev_issue_type_color = nil
        prev_issue_type_private = false
      # If we're changing to a private issue type, treat the event like a "remove"
      else
        event = "issue_type_removed"
        issue_type_id = nil
        issue_type_name = nil
        issue_type_color = nil
        issue_type_private = false
      end
    end

    ActiveRecord::Base.connected_to(role: :writing) do
      IssueEvent.create!(
        issue_id:,
        event:,
        actor_id:,
        issue_type_id:,
        issue_type_name:,
        issue_type_color:,
        issue_type_private:,
        prev_issue_type_id:,
        prev_issue_type_name:,
        prev_issue_type_color:,
        prev_issue_type_private:,
      )
    end
  end
end
