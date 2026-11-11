# typed: true
# frozen_string_literal: true

class HydroIssueCommentPinTimelineEventsJob < HydroMessageJob
  queue_as :hydro_issue_comment_pin_timeline_events
  retry_on_dirty_exit

  sig { void }
  def perform
    if FeatureFlag.vexi.enabled?(:issue_comment_pin_events_job_killswitch, default: false)
      return
    end
    created_at = Time.at(timestamp)

    state = message[:state]
    if state == :PINNED
      event = "issue_comment_pinned"
      # For scenarios where an issue comment is removed and then added in quick succession, we want to ensure that the
      # added event always comes after the removed event.
      created_at += 1.second
    elsif state == :UNPINNED
      event = "issue_comment_unpinned"
    end

    return unless event

    issue_id = message.dig(:issue, :id_value)
    issue_comment_id = message.dig(:issue_comment, :id_value)
    actor_id = message.dig(:actor, :id)

    return unless issue_id && issue_comment_id && actor_id

    subject = IssueComment.find_by(id: issue_comment_id)

    return unless subject

    issue = Issue.find_by(id: issue_id)

    return unless issue

    return if issue.pull_request?

    ActiveRecord::Base.connected_to(role: :writing) do
      IssueEvent.create!(
        issue_id:,
        event:,
        actor_id:,
        subject_id: subject.id,
        subject_type: "IssueComment",
        created_at: created_at,
      )
    end
  end
end
