# typed: true
# frozen_string_literal: true

# This job is responsible for adding sub-issue timeline events. Each sub-issue event will create two timeline
# events. One event representing the action on the parent issue and the other representing the action
# on the sub-issue.
class HydroSubIssueTimelineEventsJob < HydroMessageJob
  queue_as :hydro_sub_issue_timeline_events
  retry_on_dirty_exit

  sig { void }
  def perform
    parent_issue_id = message.dig(:source_issue, :id)
    sub_issue_id = message.dig(:target_issue, :id)
    actor_id = message.dig(:actor, :id)
    created_at = Time.at(timestamp)

    if topic == "github.v1.SubIssueAdd"
      event = "added"
      # For scenarios where a sub-issue is removed and then added in quick succession, we want to ensure that the
      # added event always comes after the removed event.
      created_at += 1.second
    elsif topic == "github.v1.SubIssueRemove"
      event = "removed"
    else
      return
    end

    parent_issue = Issue.find_by(id: parent_issue_id)
    sub_issue = Issue.find_by(id: sub_issue_id)

    # If the parent or sub-issue is not found, do not create timeline events.
    return unless parent_issue.present? && sub_issue.present?

    ActiveRecord::Base.connected_to(role: :writing) do
      # parent
      IssueEvent.create!(
        issue: parent_issue,
        event: "sub_issue_#{event}",
        subject: sub_issue,
        actor_id:,
        created_at:,
      )

      # sub-issue
      IssueEvent.create!(
        issue: sub_issue,
        event: "parent_issue_#{event}",
        subject: parent_issue,
        actor_id:,
        created_at:,
      )
    end
  end
end
