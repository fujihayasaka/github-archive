# typed: strict
# frozen_string_literal: true

module Discussion::StateDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { Discussion }

  sig { params(actor: T.nilable(User)).returns(T::Boolean) }
  def closable_by?(actor)
    async_closable_by?(actor).sync
  end

  sig { params(actor: T.nilable(User)).returns(Promise[T::Boolean]) }
  def async_closable_by?(actor)
    return T.cast(Promise.resolve(false), Promise[T::Boolean]) unless actor.present?

    Platform::Loaders::Permissions::BatchAuthorize.load(
      action: :close_discussion,
      actor: actor,
      subject: self,
    ).then(&:allow?)
  end

  sig { params(actor: T.nilable(User)).returns(T::Boolean) }
  def reopenable_by?(actor)
    async_reopenable_by?(actor).sync
  end

  sig { params(actor: T.nilable(User)).returns(Promise[T::Boolean]) }
  def async_reopenable_by?(actor)
    return T.cast(Promise.resolve(false), Promise[T::Boolean]) unless actor.present?

    Platform::Loaders::Permissions::BatchAuthorize.load(
      action: :reopen_discussion,
      actor: actor,
      subject: self,
    ).then(&:allow?)
  end

  sig do
    params(
      actor: T.nilable(User),
      reason: Discussion::StateReasonable::CloseReason,
    ).returns(T::Boolean)
  end
  def close(actor: user, reason: Discussion::StateReasonable::CloseReason::Resolved)
    return false unless closable_by?(actor)

    # If the discussion is already closed for this reason, just return early
    typed_reason = Discussion::StateReasonable::CloseReason.try_deserialize(state_reason)
    return true if closed? && reason == typed_reason

    success = T.let(false, T::Boolean)

    transaction do
      self.actor = actor
      self.state = :closed
      self.state_reason = reason.serialize
      self.closed_at = Time.current

      if save
        success = events.create(
          actor: actor,
          event_type: :closed,
          state_reason: reason.serialize,
        ).valid?
        raise ActiveRecord::Rollback unless success
      end
    end

    if success
      # If we've created a new closed event, reset the cached closer
      remove_instance_variable(:@closed_by) if instance_variable_defined?(:@closed_by)

      # Instrument for webhooks
      instrument :close, action: :closed, actor: actor
    end

    success
  end

  sig { params(actor: T.nilable(User)).returns(T::Boolean) }
  def reopen(actor: user)
    return false unless reopenable_by?(actor)
    return true unless closed?

    success = T.let(false, T::Boolean)

    transaction do
      self.actor = actor
      self.state = :open
      self.state_reason = :reopened
      self.closed_at = nil

      if save
        success = events.create(
          actor: actor,
          event_type: :reopened,
          state_reason: :reopened,
        ).valid?
        raise ActiveRecord::Rollback unless success
      end
    end

    if success
      # Instrument for webhooks
      instrument :reopen, action: :reopened, actor: actor
    end

    success
  end

  sig { returns(T.nilable(User)) }
  def closed_by
    return @closed_by if defined?(@closed_by)
    @closed_by = T.let(@closed_by, T.nilable(User))

    return @closed_by = nil unless closed?

    latest_event = events.order(id: :desc).includes(:actor).find_by(event_type: :closed)
    @closed_by = latest_event&.safe_actor
  end

  sig { returns(T::Boolean) }
  def publishable?
    draft? || scheduled?
  end
end
