# typed: true
# frozen_string_literal: true

class RepositoryUnlock < ApplicationRecord::Domain::Repositories
  include GitHub::Validations
  validates_presence_of :reason
  validates :reason, unicode3: true
  validates_presence_of :expires_at

  validate :ensure_unlocker_has_permission
  validate :ensure_staff_grant_is_active, on: :create

  belongs_to :unlocked_by, class_name: "User"
  belongs_to :repository
  belongs_to :staff_access_grant
  belongs_to :revoked_by, class_name: "User"

  scope :active, -> {
    where(revoked_by_id: nil).
    where("`repository_unlocks`.`expires_at` > NOW()")
  }
  scope :active_for_user, -> (user) {
    active.where(unlocked_by_id: user)
  }
  scope :with_active_grant, -> {
    joins(:staff_access_grant).
    where("`staff_access_grants`.`expires_at` > NOW()").
    where("`staff_access_grants`.`revoked_at` IS NULL")
  }

  DEFAULT_EXPIRY = 2.hours

  # Primary interface for creating StaffUnlock records and objects.
  #
  # staff_user: the User object of the staff user that's unlocking
  # repository: the Repository being unlocked
  # reason: the reason for the unlock
  # staff_grant: (optional) The StaffAccessGrant for the unlock. Must be
  # active.
  #
  # Returns the RepositoryUnlock object.
  def self.create_unlock(staff_user, repository, reason, staff_grant = nil)
    save_unlock(staff_user, repository, reason, staff_grant)
  end

  # Lookup an unlock by staffer/enterprise admin and repo. Existence of the unlock
  # does not mean the unlock is active and in force. Use #active?
  # to check.
  #
  # Looks up the most recent unlock associated with a staffer/enterprise admin
  # and a repository.
  #
  # Returns the RepositoryUnlock object.
  def self.with_staffer_and_repository(staffer, repository)
    where(unlocked_by_id: staffer.id, repository_id: repository.id).order("created_at DESC").limit(1).first
  end

  # Is this unlock currently active and in force?
  #
  # Returns a boolean.
  def active?
    !revoked? && expires_at > Time.now
  end

  # Revoke this unlock.
  #
  # The user that is revoking the unlock must be passed in.
  def revoke(revoking_user)
    self.revoked = true
    self.revoked_by = revoking_user
    self.revoked_at = Time.current
    save!
  end

  private

  # Saves the unlock record.
  #
  # Returns the object representing the unlock..
  def self.save_unlock(staff_user, repository, reason, staff_grant)
    expires_at = Time.now + DEFAULT_EXPIRY

    create!(unlocked_by: staff_user,
            repository: repository,
            staff_access_grant: staff_grant,
            reason: reason,
            expires_at: expires_at)
  end
  private_class_method :save_unlock

  # Ensure unlock is from a user who has permission to do so for the repository
  def ensure_unlocker_has_permission
    unless unlocked_by&.can_unlock_repos?(repository: repository)
      errors.add(:unlocked_by, "unlocker must have permission to unlock the repository")
    end
  end

  # Ensure if unlocker is staff, that the staff grant is active
  def ensure_staff_grant_is_active
    return unless unlocked_by&.staff_unlocking_repo?

    unless staff_access_grant&.active?
      errors.add(:staff_access_grant, "must be active")
    end
  end
end
