# typed: true
# frozen_string_literal: true

class Hook::Event::DiscussionCommentEvent < Hook::Event
  supports_targets *DEFAULT_TARGETS

  sig { params(desc: T.untyped).returns(T.untyped) }
  def self.description(desc = nil)
    @description = "Discussion comment created, edited, or deleted."
  end

  event_attr :action, :comment_id, :actor_id, required: true
  event_attr :changes

  sig { returns(T.untyped) }
  def comment
    @comment ||= DiscussionComment.includes(:repository, :discussion).find_by(id: comment_id)
  end

  sig { returns(T.untyped) }
  def discussion
    comment&.discussion
  end

  sig { returns(T.untyped) }
  def target_repository
    comment&.repository
  end

  sig { returns(T.untyped) }
  def actor
    @actor ||= User.find_by(id: actor_id)
  end

  sig { returns(T.untyped) }
  def changes
    return unless changes_attr
    return {} unless body_changes?

    GitHub.dogstats.increment("hooks.stale", tags: ["hook_event:discussion_comments"]) if stale_changes?

    { body: { from: changes_attr[:old_body] } }
  end

  sig { returns(T.untyped) }
  def deliverable?
    comment.present? && target_repository.present?
  end

  private

  def stale_changes?
    changes_attr[:old_body] == comment&.body
  end

  def changes_attr
    attributes.with_indifferent_access[:changes]
  end

  def body_changes?
    changes_attr[:old_body] && changes_attr[:body]
  end
end
