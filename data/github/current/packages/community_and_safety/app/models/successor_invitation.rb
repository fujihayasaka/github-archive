# typed: false
# frozen_string_literal: true

class SuccessorInvitation < ApplicationRecord::Collab

  include GitHub::RateLimitedCreation
  include Instrumentation::Model

  belongs_to :target, polymorphic: true
  belongs_to :inviter, class_name: "User"
  belongs_to :invitee, class_name: "User"
  alias_method :user, :inviter
  alias_method :user=, :inviter=

  validates_presence_of :inviter, :invitee, :target
  validate :invitee_and_inviter_distinct, :invite_exists, :spammy_user_check, :can_succeed, :verified_email_check, :invitee_is_a_user, on: :create

  scope :pending, -> { where(accepted_at: nil, declined_at: nil, canceled_at: nil) }
  scope :accepted, -> { where.not(accepted_at: nil).where(declined_at: nil, canceled_at: nil) }
  scope :declined, -> { where.not(declined_at: nil) }

  after_create_commit :send_invitation_email, :send_successor_added_email, :instrument_create
  after_destroy_commit :instrument_destroy

  class StateChangeError < StandardError; end
  class AlreadyAcceptedError < StateChangeError; end
  class AlreadyDeclinedError < StateChangeError; end
  class AlreadyCanceledError < StateChangeError; end
  class InvitePendingError < StateChangeError; end
  class ActorPermissionError < StandardError; end

  def self.help_link
    "#{GitHub.help_url}/github/setting-up-and-managing-your-github-user-account/maintaining-ownership-continuity-of-your-user-accounts-repositories"
  end

  def accept(actor: invitee)
    ensure_pending
    raise ActorPermissionError if actor != invitee

    instrument :accept

    touch :accepted_at
    send_successor_accepted_email
  end

  def decline(actor: invitee)
    ensure_pending
    raise ActorPermissionError if actor != invitee

    instrument :decline

    touch :declined_at
    send_successor_declined_email
  end

  def cancel(actor: inviter)
    ensure_pending
    raise ActorPermissionError if actor != inviter

    instrument :cancel

    touch :canceled_at
  end

  def revoke(actor: inviter)
    raise ActorPermissionError if actor != inviter
    raise InvitePendingError if pending?
    raise AlreadyCanceledError if canceled?
    raise AlreadyDeclinedError if declined?

    instrument :revoke

    touch :canceled_at
    send_successor_removed_email
  end

  def send_invitation_email
    SuccessionMailer.account_successor_invite(self).deliver_later
  end

  def instrument_create
    instrument :create
  end

  def instrument_destroy
    instrument :destroy
  end

  def event_payload
    {
      inviter: inviter,
      invitee: invitee,
      target: target
    }
  end

  def send_successor_added_email
    SuccessionMailer.account_successor_added(self).deliver_later
  end

  def send_successor_removed_email
    SuccessionMailer.account_successor_removed(self).deliver_later
  end

  def send_successor_accepted_email
    SuccessionMailer.account_successor_accepted(self).deliver_later
  end

  def send_successor_declined_email
    SuccessionMailer.account_successor_declined(self).deliver_later
  end

  def accepted?
    accepted_at? && !canceled_at?
  end

  def declined?
    declined_at?
  end

  def canceled?
    canceled_at?
  end

  def pending?
    !accepted? && !declined? && !canceled?
  end

  def inactive?
    canceled? || declined?
  end

  def revoked?
    accepted_at? && canceled_at?
  end

  def permalink(include_host: true)
    if include_host
      "#{GitHub.url}/users/#{inviter.login}/succession/invitation"
    else
      "/users/#{inviter.login}/succession/invitation"
    end
  end

  def acceptable_by?(actor)
    actor.present? && actor == invitee && !self.canceled?
  end

  # Cancels, declines, or revokes all pending or accepted invitations sent or received by a user.
  # If second user param supplied, this method locates all invites between them.
  # This is used for cases where one user blocks the other.
  def self.terminate_all(user, blockee = nil)
    sent = user.sent_successor_invitations
    received = user.received_successor_invitations

    if blockee
      sent = sent.where(invitee: blockee)
      received = received.where(inviter: blockee)
    end

    if sent.any?
      sent.pending.each(&:cancel)
      sent.accepted.each(&:revoke)
    end

    if received.any?
      received.pending.each(&:decline)
      received.accepted.each(&:revoke)
    end
  end

  private

  def ensure_pending
    return if pending?

    raise AlreadyAcceptedError if accepted?
    raise AlreadyCanceledError if canceled?
    raise AlreadyDeclinedError if declined?
  end

  def invitee_and_inviter_distinct
    if inviter == invitee
      errors.add(:base, "inviter and invitee cannot be the same user")
    end
  end

  def invite_exists
    invite = SuccessorInvitation.where(inviter: inviter).last

    if invite.present?
      if !invite.revoked? && invite.accepted? || invite.pending?
        errors.add(:base, "an invite already exists")
      end
    end
  end

  def can_succeed
    return false unless inviter.present?

    unless inviter.succeedable_by?(invitee)
      errors.add(:base, "that user cannot be appointed as a successor at this time")
    end
  end

  def spammy_user_check
    return false unless inviter.present?

    if inviter.spammy?
      errors.add(:base, "user is spammy")
    end
  end

  def verified_email_check
    return false unless inviter.present?

    if inviter.should_verify_email?
      errors.add(:base, "inviter does not have a verified email")
    end
  end

  def invitee_is_a_user
    return false unless invitee.present?

    unless invitee.user?
      errors.add(:base, "invitee must be a user")
    end
  end
end
