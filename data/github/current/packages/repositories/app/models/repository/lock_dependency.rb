# typed: true
# frozen_string_literal: true

module Repository::LockDependency
  extend T::Helpers

  requires_ancestor { Repository }

  MOVING = "moving"
  BILLING = "billing"
  RENAME = "rename"
  MIGRATING = "migrating"
  STACK_CONFIG = "stack_config"
  TRADE_RESTRICTION = "trade_restriction"
  TOS = "tos"
  TRANSFERRING_OWNERSHIP = "transferring_ownership"

  # If you extend this list with additional reasons, make sure to update the RepositoryLockReason enum
  # located in app/platform/enums/repository_lock_reason.rb
  REPOSITORY_LOCK_REASONS = [MOVING, BILLING, RENAME, MIGRATING, STACK_CONFIG, TOS, TRADE_RESTRICTION, TRANSFERRING_OWNERSHIP].freeze

  def lock!(lock_reason = nil)
    lock_including_descendants!(lock_reason)
  end

  # Public: Lock this repository.
  #
  # lock_reason - an optional reason for locking. Can be one of REPOSITORY_LOCK_REASONS.
  def lock_excluding_descendants!(lock_reason = nil)
    check_lock_reason(lock_reason)
    old_reason = self.lock_reason || "unknown"
    GitHub.logger.info(
      "Locking repository excluding descendents",
      "gh.repo.id" => self.id,
      "gh.repo.locked" => locked,
      "gh.repo.old_lock_reason" => old_reason,
      "gh.repo.new_lock_reason" => lock_reason
    )
    update! locked: true, lock_reason: lock_reason
    auditing_actor = GitHub.guarded_audit_log_staff_actor_entry(actor)
    GitHub.instrument "staff.repo_lock", auditing_actor.merge(reason: (lock_reason || "unknown"), repo: self)
    true
  end

  # Public: Lock this repository and it's descendents.
  #
  # lock_reason - an optional reason for locking. Can be  one of REPOSITORY_LOCK_REASONS.
  def lock_including_descendants!(lock_reason = nil, postorder: false)
    if postorder
      lock_descendants!(lock_reason, postorder: true)
      return lock_excluding_descendants!(lock_reason)
    end

    lock_excluding_descendants!(lock_reason)
    lock_descendants!(lock_reason)
  end

  def lock_descendants!(lock_reason = nil, postorder: false)
    if postorder
      return unlocked_forks.each { |fork| fork.lock_including_descendants!(lock_reason, postorder: true) }
    end

    forks.each { |fork| fork.lock_including_descendants!(lock_reason) }
  end

  def unlock!(postorder: false)
    unlock_including_descendants!(postorder:)
  end

  # Public: Unlock this repository.
  def unlock_excluding_descendants!
    auditing_actor = GitHub.guarded_audit_log_staff_actor_entry(actor)
    old_reason = lock_reason || "unknown"
    GitHub.instrument "staff.repo_unlock", auditing_actor.merge(reason: old_reason, repo: self)
    GitHub.logger.info(
      "Unlocking repository excluding descendents",
      "gh.repo.id" => self.id,
      "gh.repo.locked" => locked,
      "gh.repo.old_lock_reason" => old_reason,
    )
    update locked: false, lock_reason: nil
    true
  end

  # Public: Unlock this repository and it's descendents.
  def unlock_including_descendants!(postorder: false)
    if postorder
      locked_forks.each do |fork|
        fork.unlock_including_descendants!(postorder: true)
      end
      return unlock_excluding_descendants!
    end

    unlock_excluding_descendants!
    forks.each do |fork|
      fork.unlock_including_descendants!
    end
  end

  def lock_for_move
    lock_including_descendants!(MOVING)
  end

  def lock_for_billing
    lock_including_descendants!(BILLING)
  end

  def lock_for_trade_restriction
    lock_including_descendants!(TRADE_RESTRICTION)
  end

  def lock_for_migration
    lock_excluding_descendants!(MIGRATING)
  end

  def lock_for_stacks_config
    lock_excluding_descendants!(STACK_CONFIG)
  end

  def lock_for_transferring_ownership
    lock_including_descendants!(TRANSFERRING_OWNERSHIP)
  end

  def locked_on_move?
    locked? && lock_reason == MOVING
  end

  def locked_on_disk?
    locked? && !exists_on_disk?
  end

  def locked_on_billing?
    locked? && lock_reason == BILLING
  end

  def locked_on_trade_restriction?
    locked? && lock_reason == TRADE_RESTRICTION
  end

  def locked_on_rename?
    locked? && lock_reason == RENAME
  end

  def locked_on_migration?
    locked? && lock_reason == MIGRATING
  end

  def locked_on_stacks_config?
    locked? && lock_reason == STACK_CONFIG
  end

  def lock_on_transferring_ownership?
    locked? && lock_reason == TRANSFERRING_OWNERSHIP
  end

  def locked_on_nil?
    locked? && lock_reason.nil?
  end

  private

  def check_lock_reason(reason)
    is_valid = reason.nil? || REPOSITORY_LOCK_REASONS.include?(reason)
    raise ArgumentError, "lock_reason must be one of #{REPOSITORY_LOCK_REASONS.join(', ')}. Provided: #{reason}" unless is_valid
  end

  def locked_forks
    forks.where(locked: true)
  end

  def unlocked_forks
    forks.where(locked: false)
  end
end
