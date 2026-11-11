# typed: false
# frozen_string_literal: true

module User::SuccessorsDependency
  extend ActiveSupport::Concern
  include GitHub::Memoizer

  included do
    has_one :deceased_user, dependent: :destroy
  end

  # Public: Mark this user as being deceased.
  #
  # Returns nil on error or a DeceasedUser on success.
  def mark_deceased
    if deceased?
      errors.add(:deceased, "has already been set for this user")
      return nil
    end
    create_deceased_user
  end

  def deceased?
    deceased_user.present?
  end

  # Public: returns the designated successor for the user
  #
  # Returns a single record of SuccessorInvitation.
  memoize def get_successor_invitation
    successor_invitations.last
  end

  # Public: Checks whether a user is eligible to be a successor to the actor
  # A successor shouldn't be blocking the actor and vice versa, shouldn't be
  # or suspended at the time of designation
  #
  # Returns a boolean.
  def succeedable_by?(user)
    return false unless user.present?
    user != self && !user.blocking?(self) && !blocking?(user) && !user.suspended?
  end

  # Public: Returns true if this user has accepted an invitation to become
  # the inviter's account successor. Returns false if that invitation has been
  # subsequently declined, canceled, or revoked.
  #
  # Returns a boolean.
  def account_successor_for?(inviter)
    return false unless inviter.present?
    received_successor_invitations.accepted.exists?(inviter: inviter)
  end

  # Public: Returns true if this user has an accepted successor invitation.
  # Returns false if there is no existing accepted invitation.
  #
  # Returns a boolean.
  def has_successor?
    return false if get_successor_invitation.nil?

    get_successor_invitation.accepted?
  end
end
