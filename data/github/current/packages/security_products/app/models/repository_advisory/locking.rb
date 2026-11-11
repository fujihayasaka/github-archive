# typed: true
# frozen_string_literal: true

# This module provides locking functionality for repository advisories.
# When an advisory is locked, only repository administrators can edit it.
# Collaborators and other users with write access are blocked from making changes.
module RepositoryAdvisory::Locking
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { RepositoryAdvisory }

  LOCK_REASONS = %w[under-review spam invalid final].freeze

  class_methods do
    def valid_lock_reason?(reason)
      return false unless reason

      LOCK_REASONS.include?(reason)
    end
  end

  # Public: Indicates if this advisory is locked.
  def locked?
    locked_at.present?
  end

  # Public: Indicates if this advisory is lockable by a given actor.
  # An actor can lock if they have admin access to the advisory
  # and the locking feature is enabled for the repository.
  def lockable_by?(actor)
    async_lockable_by?(actor).sync
  end

  def async_lockable_by?(actor)
    return Promise.resolve(false) unless actor
    return Promise.resolve(false) unless locking_feature_enabled?

    async_adminable_by?(actor)
  end

  # If an actor can lock an advisory, they can also unlock it.
  alias_method :unlockable_by?, :lockable_by?
  alias_method :async_unlockable_by?, :async_lockable_by?

  # Public: Indicates if the advisory is locked for a given actor.
  # Returns true if the advisory is locked and the actor is not an admin.
  # Only admins can edit a locked advisory.
  # Returns false if the locking feature is disabled.
  def locked_for?(actor)
    async_locked_for?(actor).sync
  end

  def async_locked_for?(actor)
    return Promise.resolve(false) unless locking_feature_enabled?
    return Promise.resolve(false) unless locked?
    return Promise.resolve(true) unless actor

    async_adminable_by?(actor).then { |adminable| !adminable }
  end

  # Public: Checks if the locking feature is enabled for this advisory's repository.
  def locking_feature_enabled?
    FeatureFlag.vexi.enabled?(:security_advisories_locking, repository, default: false)
  end

  # Public: Returns the active lock reason for the advisory.
  def active_lock_reason
    return @active_lock_reason if defined?(@active_lock_reason)
    return unless locked?

    @active_lock_reason = events.locked.last&.value_is
  end

  # Public: Locks the advisory.
  #
  # actor  - The User locking the advisory.
  # reason - An optional String reason for locking (must be in LOCK_REASONS).
  #
  # Returns the advisory if successful, nil otherwise.
  def lock(actor, reason = nil)
    return unless lockable_by?(actor) && !locked?
    return if reason && !RepositoryAdvisory.valid_lock_reason?(reason.downcase)

    GitHub.dogstats.increment("repository_advisory", tags: ["action:lock"])

    transaction do
      events.create!(
        event: "locked",
        actor: actor,
        changed_attribute: "lock_state",
        value_is: reason.try(:downcase)
      )
      update_attribute(:locked_at, Time.current)
    end

    notify_socket_subscribers
    instrument :lock
    self
  end

  # Public: Unlocks the advisory.
  #
  # actor - The User unlocking the advisory.
  #
  # Returns the advisory if successful, nil otherwise.
  def unlock(actor)
    return unless unlockable_by?(actor) && locked?

    GitHub.dogstats.increment("repository_advisory", tags: ["action:unlock"])

    transaction do
      events.create!(
        event: "unlocked",
        actor: actor,
        changed_attribute: "lock_state"
      )
      update_attribute(:locked_at, nil)
    end

    notify_socket_subscribers
    instrument :unlock
    self
  end
end
