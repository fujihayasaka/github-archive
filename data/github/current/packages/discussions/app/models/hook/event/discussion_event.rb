# typed: true
# frozen_string_literal: true

class Hook::Event::DiscussionEvent < Hook::Event
  include GitHub::Memoizer

  supports_targets *DEFAULT_TARGETS

  DESCRIPTION_ACTIONS = [
    "created",
    "edited",
    "closed",
    "reopened",
    "pinned",
    "unpinned",
    "locked",
    "unlocked",
    "transferred",
    "answered",
    "unanswered",
    "labeled",
    "unlabeled",
    "had its category changed",
    "was deleted",
  ]

  sig { params(desc: T.untyped).returns(T.untyped) }
  def self.description(desc = nil)
    @description = "Discussion #{DESCRIPTION_ACTIONS.to_sentence(last_word_connector: ", or ")}."
  end

  event_attr :action, :discussion_id, :actor_id, required: true
  event_attr :changes
  event_attr :answer_id
  event_attr :label_id

  sig { returns(T.untyped) }
  memoize def discussion
    Discussion.includes(:repository).find_by(id: discussion_id)
  end

  sig { returns(T.untyped) }
  def target_repository
    discussion&.repository
  end

  sig { returns(T.untyped) }
  memoize def actor
    User.find_by(id: actor_id)
  end

  sig { returns(T.untyped) }
  def changes
    return unless changes_attr

    GitHub.dogstats.increment("hooks.stale", tags: ["hook_event:discussions"]) if stale_changes?

    {}.tap do |changes_hash|
      changes_hash[:body] = { from: changes_attr[:old_body] } if body_changes?
      changes_hash[:title] = { from: changes_attr[:old_title] } if title_changes?
      changes_hash[:category_id] = { from: changes_attr[:old_category_id] } if category_changes?
    end
  end

  sig { returns(T.untyped) }
  memoize def label
    Label.find_by(id: label_id)
  end

  sig { returns(T::Boolean) }
  def deliverable?
    discussion.present? && target_repository.present?
  end

  sig { returns(T.untyped) }
  memoize def source_discussion_transfer
    DiscussionTransfer.includes(:old_discussion, :old_repository).find_by(old_discussion_id: discussion_id)
  end

  sig { returns(T.untyped) }
  memoize def target_discussion_transfer
    DiscussionTransfer.includes(:new_discussion, :new_repository).find_by(new_discussion_id: discussion_id)
  end

  sig { returns(T.untyped) }
  memoize def old_category
    return unless changes_attr && category_changes?
    DiscussionCategory.find_by(id: changes[:category_id][:from])
  end

  sig { returns(T.untyped) }
  memoize def answer
    DiscussionComment.find_by(id: answer_id)
  end

  private

  def stale_changes?
    any_stale = false

    if body_changes?
      any_stale ||= changes_attr[:old_body] == discussion.body
    end

    if title_changes?
      any_stale ||= changes_attr[:old_title] == discussion.title
    end

    if category_changes?
      any_stale ||= changes_attr[:old_category] == discussion.category
    end

    any_stale
  end

  def changes_attr
    attributes.with_indifferent_access[:changes]
  end

  def body_changes?
    changes_attr[:old_body] && changes_attr[:body]
  end

  def title_changes?
    changes_attr[:old_title] && changes_attr[:title]
  end

  def category_changes?
    changes_attr[:old_category_id] && changes_attr[:category_id]
  end
end
