# typed: true
# frozen_string_literal: true

class Hook::Payload::CommitCommentPayload < Hook::Payload

  def to_payload_hash
    {
      action: hook_event.action,
      comment: api_serialize(:commit_comment_hash, hook_event.commit_comment),
    }
  end
end
