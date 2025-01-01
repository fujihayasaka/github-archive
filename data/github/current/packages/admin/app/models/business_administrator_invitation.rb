# typed: true
# frozen_string_literal: true

# Represents an invitation to an enterprise account administrator,
# where an administrator currently is either an owner or a billing manager.
class BusinessAdministratorInvitation < ApplicationRecord::Domain::Users
  include GitHub::Validations
  include GitHub::Relay::GlobalIdentification

  self.table_name = "business_member_invitations"

  enum :role, {
    owner: 1,
    billing_manager: 2,
    billing_viewer: 3, # Unused. Left over from a feature that did not ship.
    unaffiliated: 4,
  }

  # Raised when someone accepts an already-accepted invitation.
  class AlreadyAcceptedError < StandardError; end

  # Raised when someone accepts an expired invitation.
  class ExpiredError < StandardError; end

  # Raised when someone accepts or confirms a canceled invitation
  class CanceledError < StandardError; end

  # Raised when someone other than the invitee tries to accept an invitation.
  class InvalidAcceptorError < StandardError; end

  # Raised when someone tries to accept a billing manager invitation when already an owner.
  class AcceptorAlreadyOwnerError < StandardError; end

  # Raised when someone attempts to create an invalid BusinessAdministratorInvitation.
  class InvalidError < StandardError; end

  # Used for reporting when the re-invitation process fails for an expired invitation.
  class ReinvitationFailedError < StandardError; end

  belongs_to :business
  belongs_to :inviter, class_name: "User"
  belongs_to :invitee, class_name: "User"

  scope :pending, -> { where(accepted_at: nil, cancelled_at: nil, expired_at: nil) }
  scope :expired, -> { where("expired_at IS NOT NULL") }

  # This scope uses a cutoff date to considerably reduces the query cost by
  # preventing an unbounded query on created_at. Designed for use within the
  # ExpireBusinessAdminInvitationsJob.
  scope :recently_expired, -> do
    pending.where \
      "created_at BETWEEN ? AND ?",
      GitHub.invitation_expiry_cutoff.days.ago,
      GitHub.invitation_expiry_period.days.ago
  end

  scope :with_business_role, -> (*roles) {
    where(role: BusinessAdministratorInvitation.roles.values_at(*roles))
  }

  validates_length_of :email, within: 3..100, allow_blank: true
  validates_format_of :email,
    with: User::EMAIL_REGEX,
    message: "does not look like an email address",
    allow_blank: true
  validates_presence_of :business, :inviter, :role
  validates :hashed_token, presence: true, length: { is: 44 }, if: :email?
  validate :invitation_must_be_allowed!, on: :create
  validate :email_must_be_exclusive
  validates :email, unicode3: true

  before_validation :generate_token, on: :create, if: :email?

  after_create :instrument_invite_member
  after_commit :send_invitation_email, :send_nurture_request, on: :create

  # In-memory properties to support specific logic when creating new records.
  attr_accessor :reinvited_count, :skip_site_admin_check

  extend GitHub::Encoding
  force_utf8_encoding :hashed_token

  # Public: Returns all pending invitations belonging to an invitee, or any of
  # the invitee's verified UserEmail addresses or the email address supplied.
  #
  # invitee     - A User model. The owner of a pending invitation.
  # emails      - One or more email addresses to consider when searching for
  #               pending invitations.
  # include_private_emails - a Boolean indicating if we should return the private
  #                          email address for a user
  #
  # Returns an Array of pending business member invitations.
  def self.with_invitee_or_normalized_email(invitee: nil, emails: nil, include_private_emails: true)
    emails = UserEmail.safe_bulk_normalize(users: invitee, emails: emails, verified: true, include_private_emails: include_private_emails)
    return [] unless invitee || emails.any?

    if invitee.present?
      scope = where(invitee_id: invitee.id)
      scope = scope.or(where(normalized_email: emails)) if emails.any?
    else
      scope = where(normalized_email: emails)
    end

    scope.order(id: :desc)
  end

  def target_for_conditional_access
    business
  end

  def async_target_for_conditional_access
    async_business
  end

  def instrument_invite_member
    return if self.business.nil?
    business = T.must(self.business)
    if owner?
      business.instrument(:invite_admin, event_payload)
    elsif billing_manager?
      business.instrument(:invite_billing_manager, event_payload)
    elsif unaffiliated?
      business.instrument(:invite_unaffiliated_member, event_payload)
    end
  end

  def send_nurture_request
    return if self.inviter.nil? || self.business.nil?
    inviter = T.must(self.inviter)
    business = T.must(self.business)
    return unless owner? && !inviter.spammy? && business.part_of_startup_program? && stafftools_invite?

    invitee_email = invitee.present? ? T.must(invitee).email : email
    admin_email = inviter.email || invitee_email
    StartupProgramNurtureRequestJob.perform_later(admin_email: admin_email, email: invitee_email)
  end

  def send_invitation_email
    return if inviter&.spammy?

    if owner?
      BusinessMailer.invited_as_business_owner(self, token, reinvited_count).deliver_later
    elsif billing_manager?
      BusinessMailer.invited_as_business_billing_manager(self, token).deliver_later
    elsif unaffiliated?
      BusinessMailer.invited_as_business_unaffiliated_member(self, token).deliver_later
    end
  end

  # Public: Accept the invitation. This adds the invitee to the specified
  # business.
  #
  # acceptor    - Optional User who is accepting the invitation. Used for email
  #               address invites. Defaults to the invitee.
  # via_email   - Optional flag to indicate the invitation was landed on from
  #               email and should be recorded as such. Defaults to false.
  # auto_accept_duplicates - Optional flag to indicate if we should try to accept
  #                          all duplicate invites when accepting the current invite.
  #
  # Returns nothing.
  def accept(acceptor: invitee, via_email: false, auto_accept_duplicates: true)
    raise ExpiredError, "invitation expired" if expired?
    raise CanceledError, "invitation cancelled" if cancelled?
    raise AlreadyAcceptedError, "invitation already accepted" if accepted?
    raise InvalidAcceptorError, "invitee must accept invitation" unless email? || (acceptor == invitee)
    if business&.owner?(acceptor) && (billing_manager?)
      raise AcceptorAlreadyOwnerError, "acceptor is already an enterprise owner"
    end

    BusinessAdministratorInvitation.transaction do
      # We record the creator of the invitation as the actor, even though the
      # receiver of the invitation is the one logged-in and accepting it.
      # We need to nil out actor_ip, since we don't want to record the
      # logged-in user (the invitee) as the actor, and we don't know the
      # inviter's IP.
      GitHub.context.push(actor_ip: nil) do
        Audit.context.push(actor_ip: nil) do
          add_invited_member_to_business(acceptor)

          if auto_accept_duplicates
            accept_duplicate_pending_invitations \
              role: role, acceptor: acceptor, via_email: via_email
          end
        end
      end

      touch :accepted_at
    end
  end

  # Public: Has the invitation been accepted?
  #
  # Returns a boolean.
  def accepted?
    accepted_at?
  end

  # Public: Is the invitation pending?
  #
  # Returns a boolean.
  def pending?
    !accepted? && !cancelled? && !expired?
  end

  # Public: Is the invitation cancelled?
  #
  # Returns a boolean
  def cancelled?
    cancelled_at?
  end

  # Public: Is the invitation expired?
  #
  # Returns a boolean
  def expired?
    expired_at?
  end

  # Public: Cancel the invitation.
  #
  # actor - User that is cancelling the invitation.
  # notify - Boolean indicating whether we should send an email to the invitee upon cancellation.
  #
  # Returns nothing.
  def cancel(actor:, notify: true)
    return if self.business.nil?
    business = T.must(self.business)
    raise AlreadyAcceptedError, "Can't cancel an accepted invitation" if accepted?

    if owner?
      business.instrument(:cancel_admin_invitation, event_payload.merge(actor: actor))
    elsif billing_manager?
      business.instrument(:cancel_billing_manager_invitation, event_payload.merge(actor: actor))
    end

    touch(:cancelled_at) if persisted?

    if notify && !inviter&.spammy?
      if owner?
        BusinessMailer.business_admin_invitation_cancelled(self).deliver_later
      end
    end
  end

  # Public: Expire the invitation.
  #
  # Only expected to be called on persisted invitations.
  #
  # skip_reinvite - Boolean to optionally skip reinvite functionality on expiry. Defaults to false.
  #
  # Returns Boolean.
  def expire(skip_reinvite: false)
    touch :expired_at

    # Perform any re-invitation needed. #reinvite_on_expiry is
    # responsble for validating whether to re-invite.
    reinvite_on_expiry unless skip_reinvite
  end

  # How many times do we selectively re-invite after an invitation expires?
  #
  # Attempt to re-invite 3 times, meaning we will send a maximum of 4 invitation
  # emails during the initial attempt and re-attempts cycle for an owner.
  TIMES_TO_REINVITE_AFTER_INITIAL_EXPIRATION = 3

  # Create and send a new invitation based on the values in the current expired
  # invitation if needed.
  #
  # This also sets the GitHub::KV value indicating the number of re-invite
  # attempts that are remaining for the invitation.
  #
  # Returns BusinessAdministratorInvitation.
  def reinvite_on_expiry
    return unless should_be_reinvited_on_expiry?

    # Track the number of re-invites.
    # If reinvited_count is retrieved as nil, this is the first attempt to
    # re-invite, so set the count to 1. Otherwise increment the existing count by 1.
    new_reinvited_count = times_reinvited + 1

    begin
      new_invitation = BusinessAdministratorInvitation.create! \
        business: business, invitee: invitee, email: email, inviter: inviter, role: role,
        stafftools_invite: true, reinvited_count: new_reinvited_count,
        skip_site_admin_check: true

      GitHub.kv.set(new_invitation.reinvited_count_key, new_reinvited_count.to_s) # rubocop:todo GitHub/DoNotUseGlobalKv
      GlobalInstrumenter.instrument("enterprise_account.admin_reinvited", {
        old_invitation: self,
        new_invitation: new_invitation,
        times_reinvited: new_reinvited_count,
      })

      new_invitation
    rescue BusinessAdministratorInvitation::InvalidError, ActiveRecord::RecordInvalid => error
      error_for_report = ReinvitationFailedError.new \
        "Failed to re-invite recipient for BusinessAdministratorInvitation with ID #{self.id}: #{error.message}"
      Failbot.report error_for_report

      false
    end
  end

  # Should this just-expired invitation be recreated and resent?
  #
  # For enterprise accounts belonging to customers with the VSS + GHE bundle, we
  # re-invite owners a number of times if the enterprise account has no owners.
  #
  # Returns Boolean.
  def should_be_reinvited_on_expiry?
    return false unless business.present?
    return false unless expired?
    return false unless owner?
    return false if T.must(business).owners.any?

    # Check for a persisted value for the number of re-invites.
    # If it's not set, this is the first time we're re-inviting, return true.
    # If it's set, return true if < TIMES_TO_REINVITE_AFTER_INITIAL_EXPIRATION, otherwise false.
    times_reinvited < TIMES_TO_REINVITE_AFTER_INITIAL_EXPIRATION
  end

  # Public: How many times has this "recipient" been re-invited?
  #
  # Returns Integer
  def times_reinvited
    GitHub.kv.get(reinvited_count_key).value { nil }.to_i # rubocop:todo GitHub/DoNotUseGlobalKv
  end

  # Return a key for the current invitation that can be used to store the number
  # of attempts to re-create and send a new invitation.
  #
  # Used as the key for storage with GitHub::KV.
  #
  # Returns String.
  def reinvited_count_key
    [
      "business_member_invitations",
      "reinvited_count",
      "business:#{business&.id}",
      "role:#{role}",
      "invitee_id:#{invitee&.id}",
      "email:#{email}",
    ].join("/")
  end

  # Public: Can the specified user cancel the specified invitation?
  #
  # canceler - The user trying to cancel the invitation.
  #
  # Returns a boolean.
  def cancelable_by?(canceler)
    return false if self.business.nil?
    business = T.must(self.business)
    case role
    when "owner"
      business.owner?(canceler)
    when "billing_manager"
      business.owner?(canceler) || business.billing_manager?(canceler)
    when "unaffiliated"
      business.owner?(canceler)
    end
  end

  # Public: Should the inviter be shown to users?
  #
  # This will be false if:
  #   - there's no inviter (if the inviter was deleted).
  #   - the invitation was created via /stafftools (stafftools_invite is true)
  #
  # Returns a Boolean.
  def show_inviter?
    !!inviter && !stafftools_invite?
  end

  # Public: The String representation of the BusinessAdministratorInvitation. If the
  # invitation is for a user it will return the user's safe profile name. If the
  # invitation is for an email invitation it will return the email.
  #
  # Returns String.
  def email_or_invitee_name
    if email?
      email
    else
      invitee&.safe_profile_name
    end
  end

  # Public: The String representation of the BusinessAdministratorInvitation. If the
  # invitation is for a user it will return the user's login. If the
  # invitation is for an email invitation it will return the email.
  #
  # Returns String.
  def email_or_invitee_login
    if email?
      email
    else
      invitee&.login
    end
  end

  def email=(address)
    self.normalized_email = begin
        UserEmail.normalize(address)
      rescue ArgumentError
        nil # Bad email address
      end

    write_attribute(:email, address)
  end

  # Public: Fetch the hash to use for server-side persistence of the given
  # token.
  #
  # token - A string.
  #
  # Returns the hashed base64 String.
  def self.digest_token(token)
    return nil unless token.present?

    Digest::SHA256.base64digest(token.to_s)
  end

  # Public: Finds an invitation matching the supplied token. If called on an
  # ActiveRecord scope, the current scope is used to lookup the invitation.
  #
  # token - The token String generated by the BusinessAdministratorInvitation.
  #
  # Returns an BusinessAdministratorInvitation or nil if the invitation could not be
  # found.
  def self.with_token(token)
    return nil unless token.present?
    where(hashed_token: digest_token(token)).first
  end

  # Public: Stores the raw token in-memory so it's available for the duration of
  # the request. Stores a hash of the token in the database to be used to lookup
  # invitations by token.
  #
  # Returns the set token.
  def token=(token_value)
    self.hashed_token = BusinessAdministratorInvitation.digest_token(token_value.to_s)
    @token = token_value
  end
  attr_reader :token

  # Public: Resets the token and saves the invitation. Since token is only stored
  # in-memory, this is needed to regenerate links for an invitation (e.g. to resend
  # and invitation email)
  #
  # Returns a Boolean indicating if the reset was successful.
  def reset_token
    return false unless email?

    generate_token && save
  end

  # Public: Determines whether the invitation should be readable by a user
  #
  # user - user to check for access to the invitation
  #
  # Returns true if the invitation is readable by the user, false otherwise
  def readable_by?(user)
    return false if user.nil? || self.business.nil?
    return false if !user.is_a?(User) || !user.user?
    return false if GitHub.single_business_environment? && unaffiliated?
    business = T.must(self.business)

    # Email-only invitations are not associated with a user
    return true if email.present?

    # Let the invitee see their own invitation
    return true if invitee_id == user.id

    # Let business admins see any invitation.
    return true if business.owner?(user)

    # Let business billing managers see billing manager invitations.
    return true if billing_manager? && business.billing_manager?(user)

    false
  end

  def platform_type_name
    "EnterpriseAdministratorInvitation"
  end

  # Public: Returns the role attribute of the invitation for use in a message.
  #
  # Example usage:
  #
  # "You're invited to become #{invitation.role_for_message} of the enterprise."
  #
  # Returns String.
  def role_for_message
    Business.admin_role_for_message role
  end

  private

  def event_payload
    payload = {
      invitation_id: self.id,
    }
    if stafftools_invite?
      payload.update(GitHub.guarded_audit_log_staff_actor_entry(inviter))
    else
      payload.update(actor: inviter)
    end

    if email?
      payload[:email] = email
    else
      payload[:user] = invitee
      payload[:spammy] = invitee&.spammy?
    end

    payload
  end

  def invitation_must_be_allowed!
    Business::MemberInviteStatus.new(
      business, invitee, inviter: inviter, email: email,
      role: role, stafftools_invite: stafftools_invite,
      skip_site_admin_check: skip_site_admin_check
    ).validate!
  end

  def email_must_be_exclusive
    if !invitee_id? && !email?
      errors.add(:base, "invitee or email must be present")
    elsif invitee_id? && email?
      errors.add(:email, "invitee has already been set")
    end
  end

  # Private: Generates the token used to lookup email invitations.
  def generate_token
    self.token = SecureRandom.hex(20)
  end

  # Private: When accepting an email invitation, accepts pending invitations
  # for the acceptor if it exists.
  def accept_duplicate_pending_invitations(acceptor:, role:, via_email:)
    return if !email? || business.nil?

    acceptor_emails = acceptor.emails.pluck(:email)

    pending_invites = T.unsafe(T.must(business).invitations.pending.with_business_role(role))
      .with_invitee_or_normalized_email(invitee: acceptor, emails: acceptor_emails)

    # Don't include the current invitation that is being accepted.
    duplicate_invites = pending_invites - [self]

    duplicate_invites.each { |invite| invite.accept(acceptor: acceptor, via_email: via_email, auto_accept_duplicates: false) }
  end

  # Private: Add an invited member to the business, based on the role attribute.
  def add_invited_member_to_business(member)
    return if self.business.nil?
    business = T.must(self.business)
    case role
    when "owner"
      business.add_owner(member, actor: inviter, staff_action: stafftools_invite?)
    when "billing_manager"
      business.billing.add_manager(member, actor: inviter, staff_action: stafftools_invite?)
    when "unaffiliated"
      if business.two_factor_requirement_enabled? && !member.two_factor_authentication_enabled?
        raise Business::UserHasTwoFactorDisabledError, "User must have two-factor authentication enabled"
      end
      if !business.external_identity_session_owner.external_sso_requirement_met_by?(member)
        raise Business::UserHasNoExternalIdentityError, "User must have a linked external identity provisioned by the identity provider"
      end
      business.add_user_accounts([member.id], business_roles_bitfield: 0)
    end
  end
end
