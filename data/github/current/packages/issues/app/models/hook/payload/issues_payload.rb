# typed: true
# frozen_string_literal: true

class Hook::Payload::IssuesPayload < Hook::Payload

  def to_payload_hash
    {
      action: hook_event.action,
      issue: api_serialize(:issue_hash, hook_event.issue),
    }.merge(meta_payload)
  end

  def meta_payload
    case hook_event.action.to_sym
    when :labeled, :unlabeled
      label_payload
    when :assigned, :unassigned
      assignee_payload
    when :edited
      changes_payload
    when :milestoned, :demilestoned
      milestone_payload
    when :typed, :untyped
      type_payload
    when :transferred
      transferred_payload
    when :opened
      opened_payload
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

  def milestone_payload
    return {} unless hook_event.milestone

    {
      milestone: api_serialize(:milestone_hash, hook_event.milestone),
    }
  end

  def type_payload
    return {} unless hook_event.type

    {
      type: api_serialize(:type_hash, hook_event.type),
    }
  end

  def transferred_payload
    return {} unless hook_event.source_issue_transfer

    {
      changes: {
        new_issue: api_serialize(:issue_hash, hook_event.source_issue_transfer.new_issue),
        new_repository: api_serialize(:repository_hash, hook_event.source_issue_transfer.new_repository),
      },
    }
  end

  def opened_payload
    # Add old issue and old repository to the payload if the issue was opened as result
    # of an issue transfer
    return {} unless hook_event.target_issue_transfer

    {
      changes: {
        old_issue: api_serialize(:issue_hash, hook_event.target_issue_transfer.old_issue),
        old_repository: api_serialize(:repository_hash, hook_event.target_issue_transfer.old_repository),
      },
    }
  end
end
