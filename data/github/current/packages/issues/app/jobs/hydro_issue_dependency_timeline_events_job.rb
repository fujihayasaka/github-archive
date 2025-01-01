# typed: true
# frozen_string_literal: true

# This job is responsible for adding issue dependency timeline events. Each dependency event will create two timeline
# events. One event representing the action on the blocking issue and the other representing the action
# on the blocked issue.
class HydroIssueDependencyTimelineEventsJob < HydroMessageJob
  queue_as :hydro_issue_dependency_timeline_events
  retry_on_dirty_exit

  sig { void }
  def perform
    if FeatureFlag.vexi.enabled?(:issue_dependency_timeline_events_job_killswitch, default: false)
      return
    end

    blocked_issue_id = message.dig(:source_issue, :id)
    blocking_issue_id = message.dig(:target_issue, :id)
    actor_id = message.dig(:actor, :id)
    created_at = Time.at(timestamp)

    if topic == "github.v1.BlockedByAdd"
      event = "added"
      # For scenarios where a dependency is removed and then added in quick succession, we want to ensure that the
      # added event always comes after the removed event.
      created_at += 1.second
    elsif topic == "github.v1.BlockedByRemove"
      event = "removed"
    else
      return
    end

    blocking_issue = Issue.find_by(id: blocking_issue_id)
    blocked_issue = Issue.find_by(id: blocked_issue_id)

    # If the blocking or blocked issue is not found, do not create timeline events.
    return unless blocking_issue.present? && blocked_issue.present?

    ActiveRecord::Base.connected_to(role: :writing) do
      # blocking issue
      IssueEvent.create!(
        issue: blocking_issue,
        event: "blocking_#{event}",
        subject: blocked_issue,
        actor_id:,
        created_at:,
      )

      # blocked issue
      IssueEvent.create!(
        issue: blocked_issue,
        event: "blocked_by_#{event}",
        subject: blocking_issue,
        actor_id:,
        created_at:,
      )
    end
  end
end
