# typed: true
# frozen_string_literal: true

class Hook::Payload::DiscussionCommentPayload < Hook::Payload

  extend T::Sig

  sig { returns(T.untyped) }
  def to_payload_hash
    {
      action: hook_event.action,
      comment: api_serialize(:discussion_comment_hash, hook_event.comment),
      discussion: api_serialize(:discussion_hash, hook_event.discussion),
    }.merge(meta_payload)
  end

  sig { returns(T.untyped) }
  def meta_payload
    if hook_event.action.to_sym
      changes_payload
    else
      {}
    end
  end
end
