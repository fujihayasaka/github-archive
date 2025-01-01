# typed: strict
# frozen_string_literal: true

module Discussion::LockingDependency
  extend ActiveSupport::Concern
  extend T::Sig
  extend T::Helpers

  requires_ancestor { Discussion }

  # Public: Indicates if a discussion is locked for a given user.
  #         Note that a discussion can be locked either because it
  #         has been explicitly locked, or if the repository it belongs
  #         to has been archived.
  sig { params(actor: T.nilable(User)).returns(T::Boolean) }
  def locked_for?(actor)
    async_locked_for?(actor).sync
  end

  sig { params(actor: T.nilable(User)).returns(Promise[T::Boolean]) }
  def async_locked_for?(actor)
    async_repository.then do |repo|
      next true unless repo.present?

      repo.async_writable?.then do |is_writable|
        next true unless is_writable
        next false unless locked?
        next true if actor.blank?

        repo.async_writable_by?(actor).then do |is_writable|
          !is_writable
        end
      end
    end
  end

  # Public: Indicates if reactions are locked for a given user.
  sig { params(actor: T.nilable(User)).returns(T::Boolean) }
  def reactions_locked_for?(actor)
    async_reactions_locked_for?(actor).sync
  end

  sig { params(actor: T.nilable(User)).returns(Promise[T::Boolean]) }
  def async_reactions_locked_for?(actor)
    return T.cast(Promise.resolve(false), Promise[T::Boolean]) unless locked?
    return T.cast(Promise.resolve(false), Promise[T::Boolean]) if allow_reactions?

    async_repository.then do |repo|
      next true unless repo.present?

      repo.async_writable_by?(actor).then do |is_writable|
        !is_writable
      end
    end
  end

  # Public: Indicates if this discussion is lockable by a given user.
  sig { params(actor: T.nilable(User)).returns(T::Boolean) }
  def lockable_by?(actor)
    async_lockable_by?(actor).sync
  end

  sig { params(actor: T.nilable(User)).returns(Promise[T::Boolean]) }
  def async_lockable_by?(actor)
    return T.cast(Promise.resolve(false), Promise[T::Boolean]) unless actor.present?

    async_supports_announcements?.then do |is_announcements_category|
      # If this is in an announcements category, we only want to allow users
      # who can create announcements to be able to lock them
      action = is_announcements_category ? :create_discussion_announcement : :toggle_discussion_lock
      subject_promise = if is_announcements_category
        async_repository
      else
        Promise.resolve(self)
      end

      subject_promise.then do |subject|
        Platform::Loaders::Permissions::BatchAuthorize.load(
          action: action,
          actor: actor,
          subject: subject,
        ).then(&:allow?)
      end
    end
  end

  # If a user can lock a discussion, they can also unlock it.
  alias :unlockable_by? :lockable_by?
  alias :async_unlockable_by? :async_lockable_by?

  # Public: Locks a discussion.
  sig { params(actor: T.nilable(User), allow_reactions: T::Boolean).returns(T::Boolean) }
  def lock(actor:, allow_reactions: false)
    return false unless lockable_by?(actor)
    success = T.let(false, T::Boolean)
    successful_state_change = T.let(false, T::Boolean)

    transaction do
      self.actor = actor
      self.allow_reactions = allow_reactions
      self.locked_at = Time.current

      if save
        success = events.create(actor: actor, event_type: :locked).valid?
        raise ActiveRecord::Rollback unless success
      end
    end

    if success
      notify_socket_subscribers
      synchronize_search_index
      instrument :lock, action: :locked, actor: actor
    end

    success
  end

  # Public: Unlocks a discussion.
  sig { params(actor: T.nilable(User)).returns(T::Boolean) }
  def unlock(actor:)
    return false unless unlockable_by?(actor)
    success = T.let(false, T::Boolean)
    successful_state_change = T.let(false, T::Boolean)

    transaction do
      self.actor = actor
      self.allow_reactions = true
      self.locked_at = nil

      if save
        success = events.create(actor: actor, event_type: :unlocked).valid?
        raise ActiveRecord::Rollback unless success
      end
    end

    if success
      notify_socket_subscribers
      synchronize_search_index
      instrument :unlock, action: :unlocked, actor: actor
    end

    success
  end

  # Public: Indicates if this discussion is locked.
  sig { returns(T::Boolean) }
  def locked?
    locked_at.present?
  end

  # Public: Implement active_lock_reason for the `Lockable` GraphQL interface.
  #         Note: Discussions do not have lock reasons, so we default to "resolved"
  #         from `Issue::LOCK_REASONS`.
  sig { returns(T.nilable(String)) }
  def active_lock_reason
    return unless locked?
    "resolved"
  end
end
