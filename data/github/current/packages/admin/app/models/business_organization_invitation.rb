# typed: true
# frozen_string_literal: true

require "github/enterprise_accounts/kv"

# An invitation for an Organization to join a Business.
#
# It is created by a Business owner, and its status flows like this:
#
#     Organization admin          Business owner
#           accepts                  confirms
# CREATED -----------> ACCEPTED -----------------> CONFIRMED
#    |                     |
#    | Organization admin  | Business owner
#    | declines            | declines
#    |                     V
#    +---------------> CANCELED
#
# An invitation becomes expired, either:
#
# - INVITATION_EXPIRY_PERIOD days after it is created if not accepted
# - INVITATION_EXPIRY_PERIOD days after it is accepted if not confirmed

class BusinessOrganizationInvitation < ApplicationRecord::Domain::Users
  include GitHub::Relay::GlobalIdentification
  include ActionView::Helpers::DateHelper
  include ActionView::Helpers::TextHelper

  # The number of days before a created or accepted invitation expires.
  INVITATION_EXPIRY_PERIOD = 30

  # Number of days between sending reminders for expiring invitations.
  INVITATION_REMINDER_PERIOD = 3

  # The number of days after the invitation expiration date to consider for
  # invitations to be considered "recently expired". Helps avoid unbounded
  # queries.
  INVITATION_EXPIRY_CUTOFF = INVITATION_EXPIRY_PERIOD + 2

  # Cutoff period in days for any invitation confirmed or canceled at an earlier date.
  REDUNDANT_INVITATION_CUTOFF = 365

  belongs_to :business
  belongs_to :inviter, class_name: "User"
  belongs_to :invitee, class_name: "Organization"
  belongs_to :completed_by, class_name: "User"

  validates_presence_of :business, :inviter, :invitee
  validate :ensure_business_can_invite_orgs
  validate :inviter_must_be_business_admin
  validate :organization_not_business_member, unless: :completed?
  validate :organization_not_already_invited_to_business
  validate :organization_not_upgrade_to_business_in_progress
  validate :validate_business_has_sufficient_seats
  validate :business_can_accept_marketplace_purchases
  validate :organization_has_no_outstanding_balance
  validate :organization_not_in_dunning

  after_commit :send_invitation_email, on: :create
  after_create :instrument_invite_organization

  # Pending invitations are those not in the final states
  scope :pending, -> { where(confirmed_at: nil, canceled_at: nil, expired_at: nil, completed_at: nil) }

  # Invitations pending acceptance by an org admin
  scope :pending_acceptance, -> {
    where(
      accepted_at: nil,
      confirmed_at: nil,
      canceled_at: nil,
      expired_at: nil,
      completed_at: nil
    )
  }

  # Invitations pending completion by sales-ops
  scope :pending_completion, -> {
    where("confirmed_at IS NOT NULL").
    where(
      completed_at: nil
    )
  }

  scope :expired, -> { where("expired_at IS NOT NULL") }

  # This scope uses a cutoff date to considerably reduce the query cost by
  # preventing unbounded queries. Designed for use within the
  # ExpireBusinessOrganizationInvitationsJob.
  scope :recently_expired, -> do
    pending.where <<-SQL, from: INVITATION_EXPIRY_CUTOFF.days.ago, to: INVITATION_EXPIRY_PERIOD.days.ago
      (
        accepted_at IS NULL AND created_at BETWEEN :from AND :to
      ) OR (
        accepted_at BETWEEN :from AND :to
      )
    SQL
  end

  scope :with_status, ->(status) {
    case status&.to_sym
    when :created
      where(confirmed_at: nil, accepted_at: nil, canceled_at: nil, expired_at: nil)
    when :accepted
      where.not(accepted_at: nil).where(confirmed_at: nil, canceled_at: nil, expired_at: nil, completed_at: nil)
    when :confirmed
      where.not(confirmed_at: nil)
    when :canceled
      where.not(canceled_at: nil)
    when :expired
      where.not(expired_at: nil)
    when :completed
      where.not(completed_at: nil)
    else
      none
    end
  }

  # This scope filters canceled and expired organization invitations based on the
  # REDUNDANT_INVITATION_CUTOFF time. Invitations canceled or expired at an earlier time than the
  # REDUNDANT_INVITATION_CUTOFF time are considered redundant.
  scope :redundant_invitations, -> {
    where(
      "canceled_at < ? OR expired_at < ?",
      REDUNDANT_INVITATION_CUTOFF.days.ago,
      REDUNDANT_INVITATION_CUTOFF.days.ago
    )
  }

  # Raised when someone attempts to accept/confirm an expired invitation.
  class ExpiredError < StandardError; end

  # Raised when someone accepts an already-accepted invitation.
  class AlreadyAcceptedError < StandardError; end

  # Raised when someone accepts, confirms or cancels an already-confirmed invitation.
  class AlreadyConfirmedError < StandardError; end

  # Raised when someone confirms an unaccepted invitation.
  class NotYetAcceptedError < StandardError; end

  # Raised when someone completes an already-completed invitation.
  class AlreadyCompletedError < StandardError; end

  # Raised when someone completes an unconfirmed invitation.
  class NotYetConfirmedError < StandardError; end

  # Raised when someone other than the invitee tries to accept or cancel an invitation.
  class InvalidActorError < StandardError; end

  # Raised when someone accepts or confirms a canceled invitation
  class CanceledError < StandardError; end

  # Raised when someone accepts or confirms an invitation from a business that the org already belongs to
  class AlreadyBusinessMemberError < StandardError; end

  # Raised if business can no longer extend this invitation
  class InvalidInviterError < StandardError; end

  # Raised when not enough seats are available in this business to add an Organization
  class InsufficientAvailableSeatsError < StandardError; end

  # Raised when the Business is flagged spammy
  class BusinessIsSpammyError < StandardError; end

  # Raised when the organization has an upgrade to enterprise in progress
  class OrganizationUpgradeToBusinessInProgressError < StandardError; end

  # Raised when the organization has an outstanding balance
  class OrganizationHasOutstandingBalanceError < StandardError; end

  # Raised when the organization is in dunning
  class OrganizationIsInDunningError < StandardError; end

  def ensure_business_can_invite_orgs
    return if self.business.blank?
    business = T.must(self.business)
    if business.spammy?
      errors.add(:base, "This enterprise has been flagged and cannot invite organizations.")
    elsif !business.default_managed?
      errors.add(:base, "Organization invitations are not available for externally managed enterprises.")
    end
  end

  def inviter_must_be_business_admin
    return if inviter.blank? || business.blank?
    unless T.must(business).owner?(T.must(inviter))
      errors.add(:inviter, "must be an administrator of the enterprise.")
    end
  end

  def organization_not_business_member
    return unless self.invitee
    invitee = T.must(self.invitee)
    if invitee.business
      errors.add(:base, "Organization #{invitee.display_login} already belongs to an enterprise.")
    end
  end

  def organization_not_already_invited_to_business
    return if invitee.blank? || business.blank?
    business = T.must(self.business)
    invitee = T.must(self.invitee)
    if business.pending_organization_invitation_for(invitee)
      errors.add(:base, "Organization #{invitee.display_login} has already been invited to this enterprise.")
    end
  end

  def organization_not_upgrade_to_business_in_progress
    return unless invitee
    invitee = T.must(self.invitee)
    if invitee.upgrade_to_enterprise_in_progress?
      errors.add(:base, "Organization #{invitee.display_login} can not be invited because it has an upgrade to enterprise in progress.")
    end
  end

  def validate_business_has_sufficient_seats
    return if invitee.blank? || business.blank?

    business = T.must(self.business)
    invitee = T.must(self.invitee)
    unless business_has_sufficient_seats?
      seats_needed = business.additional_licenses_required_for_organization(invitee)
      errors.add :business, "needs #{pluralize(seats_needed, "additional seat")} to add #{invitee.display_login}."
    end
  end

  # Organizations with Marketplace apps can only be transferred to self-serve enterprises
  # if not currently in a trial period, has valid payment information
  def business_can_accept_marketplace_purchases
    return if invitee&.active_marketplace_listing_subscription_items&.none?
    return if business.nil? || !business&.self_serve_payment?

    business = T.must(self.business)
    msg = "cannot accept organizations with marketplace purchases"
    if business.trial?
      errors.add :business, "#{msg} during the trial period."
    end

    unless business.has_valid_payment_method?
      errors.add :business, "#{msg} without a valid payment method."
    end
  end

  def organization_has_no_outstanding_balance
    if organization_has_outstanding_balance?
      errors.add(:base, "Organization #{invitee&.display_login} cannot be invited because it has an outstanding balance.")
    end
  end

  def organization_not_in_dunning
    if organization_in_dunning?
      errors.add(:base, "Organization #{invitee&.display_login} cannot be invited because it is overdue for payment.")
    end
  end

  def accept(acceptor)
    return if invitee.blank? || business.blank?
    business = T.must(self.business)
    invitee = T.must(self.invitee)
    raise ExpiredError, "invitation has expired" if expired?
    raise AlreadyConfirmedError, "invitation already confirmed" if confirmed?
    raise AlreadyAcceptedError, "invitation already accepted" if accepted?
    raise CanceledError, "invitation has been canceled" if canceled?
    raise AlreadyBusinessMemberError, "organization already part of an enterprise" if invitee.business
    raise InvalidActorError, "acceptor not allowed to accept this invitation" unless invitee.adminable_by?(acceptor)
    raise InsufficientAvailableSeatsError, "enterprise has insufficient seats" unless business_has_sufficient_seats?
    raise OrganizationUpgradeToBusinessInProgressError, "organization has an upgrade to enterprise in progress" if invitee.upgrade_to_enterprise_in_progress?
    raise OrganizationHasOutstandingBalanceError, "organization has an outstanding balance" if organization_has_outstanding_balance?
    raise OrganizationIsInDunningError, "organization is overdue for payment" if organization_in_dunning?

    touch :accepted_at
    set_last_reminded_at(nil)
    invitee.instrument(:accept_business_invitation, { business: business, actor: acceptor })
  end

  def confirm(confirmer)
    return if invitee.blank? || business.blank?
    business = T.must(self.business)
    invitee = T.must(self.invitee)
    raise BusinessIsSpammyError, "enterprise is flagged and cannot confirm invitation" if business.spammy?
    raise ExpiredError, "invitation has expired" if expired?
    raise AlreadyConfirmedError, "invitation already confirmed" if confirmed?
    raise CanceledError, "invitation has been canceled" if canceled?
    raise NotYetAcceptedError, "invitation must be accepted before confirmation" unless accepted?
    raise AlreadyBusinessMemberError, "organization already part of an enterprise" if invitee.business
    raise InvalidActorError, "confirmer not allowed to confirm this invitation" unless business.adminable_by?(confirmer)
    raise InsufficientAvailableSeatsError, "enterprise has insufficient seats" unless business_has_sufficient_seats?
    raise OrganizationUpgradeToBusinessInProgressError, "organization has an upgrade to enterprise in progress" if invitee.upgrade_to_enterprise_in_progress?
    raise OrganizationHasOutstandingBalanceError, "organization has an outstanding balance" if organization_has_outstanding_balance?
    raise OrganizationIsInDunningError, "organization is overdue for payment" if organization_in_dunning?

    completed = invitee.plan.free? || business.customer&.self_serve_payment?
    BusinessOrganizationInvitation.transaction do
      update_attribute :invitee_billing_type, invitee.billing_type
      business.add_organization(invitee, actor: confirmer)
      # Transfer all of the organization's marketplace purchases to the business if it is a self-serve enterprise
      business.transfer_marketplace_purchases_from_org_to_business(invitee, confirmer)

      if business.trial?
        invitee.suspend_billing
      else
        invitee.plan = "business_plus"
      end
      invitee.expire_active_coupon
      invitee.save
      touch :confirmed_at
      touch :completed_at if completed

      implicitly_refused_invitations = invitee.business_invitations.pending.where.not(business: business)
      implicitly_refused_invitations.each { |invitation| invitation.cancel(confirmer) }
    end

    Billing::EnterpriseCloudTrialCheckJob.perform_later(invitee.id)
    invitee.instrument :confirm_business_invitation, { business: business, actor: confirmer, invitation_id: self.id }
  end

  def complete(completer)
    raise InvalidActorError, "completer not allowed to complete this invitation" unless completer.site_admin?
    raise CanceledError, "invitation has been canceled" if canceled?
    raise NotYetConfirmedError, "invitation has not been confirmed yet." unless confirmed?
    raise AlreadyCompletedError, "invitation has already been completed." if completed?

    BusinessOrganizationInvitation.transaction do
      touch :completed_at
      update(completed_by_id: completer.id)
    end
  end

  def status
    if expired_at.present?
      :expired
    elsif completed_at.present?
      :completed
    elsif confirmed_at.present?
      :confirmed
    elsif canceled_at.present?
      :canceled
    elsif accepted_at.present?
      :accepted
    else
      :created
    end
  end

  def accepted?
    accepted_at.present?
  end

  def confirmed?
    confirmed_at.present?
  end

  def canceled?
    canceled_at.present?
  end

  def expired?
    expired_at.present?
  end

  def completed?
    completed_at.present?
  end

  # Public: Expire the invitation.
  #
  # Only expected to be called on persisted invitations.
  #
  # Returns Boolean.
  def expire
    touch :expired_at
  end

  # Public: Does this invitation need a reminder to be sent now?
  #
  # Returns Boolean.
  def needs_reminder?
    if status == :created
      last_notified = last_reminded_at || created_at
      return true if last_notified < INVITATION_REMINDER_PERIOD.days.ago
    elsif status == :accepted
      last_notified = last_reminded_at || accepted_at
      return true if last_notified < INVITATION_REMINDER_PERIOD.days.ago
    end

    false
  end

  # Public: Send an email to remind the relevant people that the invitation is
  # expiring.
  #
  # Returns nothing.
  def send_expiration_reminder
    return if self.business.blank?
    business = T.must(self.business)
    return if business.spammy?
    return if business.suspended?

    if status == :created
      set_last_reminded_at(DateTime.now)
      # If it's not yet accepted, remind the org
      BusinessMailer.organization_invitation_pending_acceptance_reminder(self).deliver_later
    elsif status == :accepted
      set_last_reminded_at(DateTime.now)
      # If it's accepted but not yet confirmed, remind the enterprise
      BusinessMailer.organization_invitation_pending_confirmation_reminder(self).deliver_later
    end
  end

  # Public: Get the distance of time until the invitation expires in words.
  #
  # Returns String.
  def until_expiry_in_words
    if status == :created
      expires = T.must(created_at) + INVITATION_EXPIRY_PERIOD.days
      distance_of_time_in_words(DateTime.now, expires)
    elsif status == :accepted
      expires = T.must(accepted_at) + INVITATION_EXPIRY_PERIOD.days
      distance_of_time_in_words(DateTime.now, expires)
    end
  end

  # Public: Get the time at which the last reminder for this invitation was sent.
  #
  # Returns DateTime.
  def last_reminded_at
    return unless stored = EnterpriseAccounts::KV.store.get(last_reminded_key).value { nil }
    DateTime.parse stored
  end

  # Public: Set the last time at which a reminder was sent for the invitation.
  #
  # last_reminded_at - DateTime representing last time reminder was sent, or
  #                    nil to clear last_reminded_at.
  #
  # Returns nothing.
  def set_last_reminded_at(last_reminded_at)
    if last_reminded_at.blank?
      EnterpriseAccounts::KV.store.del(last_reminded_key)
    else
      EnterpriseAccounts::KV.store.set(last_reminded_key, last_reminded_at.to_s)
    end
  end

  # Public: Cancel a pending invitation.
  #
  # actor - User that is cancelling the invitation.
  # initiated_from - Optional String representing the origin of the cancellation.
  #                  Must be either "enterprise" or "organization" if provided.
  #
  # Returns nothing.
  def cancel(actor, initiated_from = nil)
    return if invitee.blank? || business.blank?
    business = T.must(self.business)
    invitee = T.must(self.invitee)
    if !initiated_from.nil? && !%w(enterprise organization).include?(initiated_from)
      raise ArgumentError, %Q[initiated_from must be either "enterprise" or "organization"]
    end
    raise ExpiredError, "invitation has expired" if expired?
    raise CanceledError, "invitation has been canceled" if canceled?
    raise AlreadyConfirmedError, "invitation has already been confirmed" if confirmed?
    raise InvalidActorError, "actor not allowed to cancel this invitation" if !invitee.adminable_by?(actor) && !business.owner?(actor)

    touch :canceled_at

    payload = {
      business: business,
      actor: actor
    }
    payload[:initiated_from] = initiated_from if initiated_from.present?
    invitee.instrument(:cancel_business_invitation, payload)
  end

  def send_invitation_email
    return if inviter.nil? || inviter&.spammy?

    BusinessMailer.invited_organization(self).deliver_later
  end

  # Public: Should the inviter be shown to organizations?
  #
  # This will be false if:
  #   - there's no inviter (which can happen if the inviter
  #     is deleted after sending the invitation).
  #
  # Returns a Boolean.
  def show_inviter?
    !!inviter
  end

  def instrument_invite_organization
    invitee&.instrument(:invite_to_business, { business: business, actor: inviter })
  end

  # The number of unique users in the invited organization that are not already
  # members of the business.
  #
  # Returns an Integer.
  def needed_seat_count
    @needed_seat_count ||= T.must(business).additional_licenses_consumed_by_organization(T.must(invitee))
  end

  def platform_type_name
    "EnterpriseOrganizationInvitation"
  end

  private

  # Private: Get a key for the invitation to be used to store the timestamp of
  # the last reminder sent.
  #
  # Used as the key for storage with GitHub::KV.
  #
  # Returns String.
  def last_reminded_key
    [
      "business_organization_invitations",
      "last_reminded",
      self.id,
    ].join("/")
  end

  def business_has_sufficient_seats?
    return if invitee.blank? || business.blank?
    return true if T.must(business).metered_plan? && !T.must(business).trial?
    T.must(business).has_sufficient_licenses_for_organization?(T.must(invitee))
  end

  def organization_has_outstanding_balance?
    return if invitee.blank?
    T.must(invitee).balance.positive?
  end

  def organization_in_dunning?
    return if invitee.blank? || !invitee.is_a?(Organization)
    T.must(invitee).dunning?
  end
end
