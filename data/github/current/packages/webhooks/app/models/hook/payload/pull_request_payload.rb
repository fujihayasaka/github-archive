# typed: true
# frozen_string_literal: true

class Hook::Payload::PullRequestPayload < Hook::Payload

  def to_payload_hash
    {
      action: hook_event.action,
      number: hook_event.pull_request.number,
      pull_request: api_serialize(:pull_request_hash, hook_event.pull_request, full: true, hook: true, show_merge_settings: true),
    }.merge(meta_payload)
  end

  def meta_payload
    case hook_event.action.to_sym
    when :labeled, :unlabeled
      label_payload
    when :assigned, :unassigned
      assignee_payload
    when :review_requested, :review_request_removed
      requested_reviewer_payload
    when :edited
      changes_payload
    when :synchronize
      synchronize_payload
    when :auto_merge_disabled
      auto_merge_disabled_payload
    when :milestoned, :demilestoned
      milestone_payload
    when :dequeued
      dequeued_payload
    else
      {}
    end
  end

  def label_payload
    return {} unless hook_event.label

    {
      label: api_serialize(:label_hash, hook_event.label, repo: hook_event.label.repository),
    }
  end

  def assignee_payload
    return {} unless hook_event.assignee

    {
      assignee: api_serialize(:user_hash, hook_event.assignee),
    }
  end

  def requested_reviewer_payload
    return {} unless hook_event.requested_reviewer

    return { requested_reviewer: api_serialize(:user_hash, hook_event.requested_reviewer) } if hook_event.requested_reviewer.is_a?(User)
    return { requested_team: api_serialize(:team_hash, hook_event.requested_reviewer) } if hook_event.requested_reviewer.is_a?(Team)
  end

  def synchronize_payload
    return {} unless hook_event.before && hook_event.after

    {
      before: hook_event.before,
      after: hook_event.after,
    }
  end

  def auto_merge_disabled_payload
    return {} unless hook_event.reason

    {
      reason: hook_event.reason
    }
  end

  def milestone_payload
    return {} unless hook_event.milestone

    {
      milestone: api_serialize(:milestone_hash, hook_event.milestone),
    }
  end

  def dequeued_payload
    return {} unless hook_event.reason

    {
      reason: hook_event.reason
    }
  end
end
