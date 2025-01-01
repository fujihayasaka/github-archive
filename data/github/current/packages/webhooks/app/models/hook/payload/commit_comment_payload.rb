# typed: true
# frozen_string_literal: true

class Hook::Payload::CommitCommentPayload < Hook::Payload

  def to_payload_hash
    {}.tap do |payload|
      payload[:action]  = hook_event.action
      payload[:changes] = hook_event.changes if hook_event.changes
      payload[:comment] = api_serialize(:commit_comment_hash, hook_event.commit_comment)
    end
  end
end
