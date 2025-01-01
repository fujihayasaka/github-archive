# typed: true
# frozen_string_literal: true

class Hook::Payload::IssueCommentPayload < Hook::Payload

  def to_payload_hash
    {}.tap do |payload|
      owner = hook_event.target_organization || hook_event.target_repository.owner
      options = { author_association_viewer: owner.organization? ? owner.admins.first : owner }

      payload[:action]  = hook_event.action
      payload[:changes] = hook_event.changes if hook_event.changes
      payload[:issue]   = api_serialize(:issue_hash, hook_event.issue)
      payload[:comment] = api_serialize(:issue_comment_hash, hook_event.issue_comment, options)
    end
  end
end
