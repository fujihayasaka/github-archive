# typed: true
# frozen_string_literal: true

class OrganizationInvitation::AcceptInvitationStatus
  # Internal: Successful statuses.
  SUCCESSFUL = [:success]

  # Internal: Error messages for each status.
  ERROR_MESSAGES = {
      already_accepted: "This invitation has already been accepted",
      blocked: "Your account is not eligible to accept this invitation.",
      expired: "This invitation has expired",
      invalid_acceptor: "Invitee must accept invitation",
      no_2fa: ::Team::AddMemberStatus::MESSAGES[:no_2fa],
      trade_controls_restricted: TradeControls::Notices.notice_as_plaintext(:org_invite_restricted),
      user_already_linked: "This user is already linked to a different identity.",
      email_not_associated_with_logged_in_user: OrganizationInvitation::EMAIL_NOT_VERIFIED_ERROR_MESSAGE,
      spammy_invitee: OrganizationInvitation::SPAMMY_INVITEE_ERROR_MESSAGE,
  }

  # Public: A Symbol.
  attr_reader :status

  def initialize(status, message = nil)
    @status = status
    @message = message
  end

  private :initialize

  # Public: Did an error occur while accepting the invitation?
  #
  # Returns a Boolean.
  def error?
    !success?
  end

  # Public: The error message to display to a user.
  #
  # Returns a String | nil.
  def error
    return unless error?
    ERROR_MESSAGES[status] || @message
  end

  # Public: Was the invitation successfully accepted?
  #
  # Returns a Boolean.
  def success?
    SUCCESSFUL.include?(status)
  end

  # Public: It's all good.
  #
  # Returns an AcceptInvitationStatus.
  SUCCESS = new(:success)

  # Public: A user block is preventing the invitation from being accepted.
  #         This is returned when the acceptor is blocked by the organization.
  #
  # Returns an AcceptInvitationStatus.
  BLOCKED = new(:blocked)

  # Public: An expired invite is preventing the user from joining the org.
  #
  # Returns an AcceptInvitationStatus.
  EXPIRED = new(:expired)

  # Public: The acceptor does not meet the two factor requirements of the org
  #
  # Returns an AcceptInvitationStatus.
  NO_2FA = new(:no_2fa)

  # Public: The invitation has already been accepted
  #
  # Returns an AcceptInvitationStatus.
  ALREADY_ACCEPTED = new(:already_accepted)

  # Public: Trade Control Restrictions prevent acceptance of this invitation
  #
  # Returns an AcceptInvitationStatus.
  TRADE_CONTROLS_RESTRICTED = new(:trade_controls_restricted)

  # Public: only the invitee can accept the invitation. Does not apply to email invites.
  #
  # Returns an AcceptInvitationStatus.
  INVALID_ACCEPTOR = new(:invalid_acceptor)

  # Public: only the invitee can accept the invitation that is not already linked to a different external identity record.
  #
  # Returns an AcceptInvitationStatus.
  USER_ALREADY_LINKED = new(:user_already_linked)

  # Public
  EMAIL_NOT_ASSOCIATED_WITH_LOGGED_IN_USER = new(:email_not_associated_with_logged_in_user)

  # Public: the user accepting the invitation cannot be marked as spammy
  SPAMMY_INVITEE = new(:spammy_invitee)
end
