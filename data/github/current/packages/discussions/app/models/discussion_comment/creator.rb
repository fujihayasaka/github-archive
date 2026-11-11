# typed: strict
# frozen_string_literal: true

class DiscussionComment::Creator
  include ActiveModel::Validations
  include GitHub::Memoizer

  validate :ensure_valid_state_reason

  sig do
    params(
      discussion: Discussion,
      actor: User,
      body: T.nilable(String),
      parent_comment_id: T.nilable(Integer),
      state_reason: T.nilable(String),
      post_as_admin: T.nilable(T::Boolean),
    ).void
  end
  def initialize(
    discussion:,
    actor:,
    body: nil,
    parent_comment_id: nil,
    state_reason: nil,
    post_as_admin: false
  )
    @discussion         = discussion
    @actor              = actor
    @body               = body
    @parent_comment_id  = parent_comment_id
    @state_reason       = state_reason
    @post_as_admin      = post_as_admin
  end

  sig { returns(Discussion) }
  attr_reader :discussion

  sig { returns(User) }
  attr_reader :actor

  sig { returns(T.nilable(String)) }
  attr_reader :body

  sig { returns(T.nilable(Integer)) }
  attr_reader :parent_comment_id

  sig { returns(T.nilable(String)) }
  attr_reader :state_reason

  sig { returns(T.nilable(T::Boolean)) }
  attr_reader :post_as_admin

  sig { returns(DiscussionComment) }
  memoize def comment
    discussion.comments.build(
      user: actor,
      body: body,
      parent_comment_id: parent_comment_id,
      post_as_admin: post_as_admin,
    )
  end

  sig { returns(T::Boolean) }
  def save
    return false unless valid?

    success = T.let(false, T::Boolean)

    DiscussionComment.transaction do
      if create_comment? && !comment.save
        errors.merge!(comment.errors)
        raise ActiveRecord::Rollback
      end

      if state_reason.present? && !update_state
        errors.add(:discussion, "state could not be updated")
        raise ActiveRecord::Rollback
      end

      success = true
    end

    success
  end

  private

  sig { returns(T::Boolean) }
  def create_comment?
    return true if body.present?
    state_reason.blank?
  end

  sig { returns(T::Boolean) }
  def update_state
    if state_reason == Discussion::StateReasonable::StateReason::Reopened.serialize
      discussion.reopen(actor: actor)
    else
      typed_reason = Discussion::StateReasonable::CloseReason.deserialize(state_reason)
      discussion.close(actor: actor, reason: typed_reason)
    end
  end

  sig { void }
  def ensure_valid_state_reason
    return unless state_reason.present?

    valid_reasons = Discussion::StateReasonable::StateReason.values.map(&:serialize)
    unless valid_reasons.include?(state_reason)
      errors.add(:state_reason, "must be a valid reason")
    end
  end
end
