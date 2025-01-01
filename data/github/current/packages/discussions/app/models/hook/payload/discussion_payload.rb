# typed: true
# frozen_string_literal: true

class Hook::Payload::DiscussionPayload < Hook::Payload

  extend T::Sig

  sig { returns(T.untyped) }
  def to_payload_hash
    {
      action: hook_event.action,
      discussion: api_serialize(:discussion_hash, hook_event.discussion),
    }.merge(meta_payload)
  end

  sig { returns(T.untyped) }
  def meta_payload
    case hook_event.action.to_sym
    when :created
      created_payload
    when :edited
      changes_payload
    when :category_changed
      category_changed_payload
    when :transferred
      transferred_payload
    when :answered
      answered_payload
    when :unanswered
      unanswered_payload
    when :labeled, :unlabeled
      label_payload
    else
      {}
    end
  end

  sig { returns(T.untyped) }
  def label_payload
    return {} unless hook_event.label

    {
      label: api_serialize(:label_hash, hook_event.label, repo: hook_event.label.repository),
     }
  end

  sig { returns(T.untyped) }
  def created_payload
    transfer = hook_event.target_discussion_transfer
    return {} unless transfer

    {
      changes: {
        old_discussion: api_serialize(:discussion_hash, transfer.old_discussion),
        old_repository: api_serialize(:repository_hash, transfer.old_repository),
      }
    }
  end

  sig { returns(T.untyped) }
  def category_changed_payload
    {
      changes: {
        category: { from: api_serialize(:discussion_category_hash, hook_event.old_category) }
      }
    }
  end

  sig { returns(T.untyped) }
  def transferred_payload
    transfer = hook_event.source_discussion_transfer
    return {} unless transfer

    {
      changes: {
        new_discussion: api_serialize(:discussion_hash, transfer.new_discussion),
        new_repository: api_serialize(:repository_hash, transfer.new_repository),
      }
    }
  end

  sig { returns(T.untyped) }
  def answered_payload
    {
      answer: api_serialize(:discussion_comment_hash, hook_event.answer),
    }
  end

  sig { returns(T.untyped) }
  def unanswered_payload
    {
      old_answer: api_serialize(:discussion_comment_hash, hook_event.answer),
    }
  end
end
