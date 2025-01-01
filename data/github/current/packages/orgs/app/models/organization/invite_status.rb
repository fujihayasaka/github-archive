# typed: true
# frozen_string_literal: true

# This class represents whether or not an invitation with the specified
# organization, invitee, and teams can be created.
#
# The core of this class is the `errors` method. Make sure to read its docs to
# understand its possible return values.
class Organization::InviteStatus
  attr_reader :invitee, :email, :inviter, :organization, :teams, :external_identity

  ERROR_MESSAGES = {
    invalid_teams: "All teams on the invitation must be on this organization",
    already_on_org: "Invitee is already a part of this organization",
    email_already_on_org: "A user with this email addresss is already a part of this organization",
    invitee_is_not_a_user: "Invitee must be a user",
    insufficient_inviter_permissions: "Inviter has insufficient permissions",
    already_has_role: "Invitee already has that role in this organization",
    invitee_and_email_provided: "Invite can only be delivered to either user or email",
    invitee_or_email_required: "Invite requires either user or email",
    invalid_email: "Invite must be for a valid email address",
    invitee_opted_out: "Invitee must not be opted out",
    blocked_from_org: "The invitee must not be blocked by the organization",
    inviter_requires_verification: "A verified email address is required to invite members via email address",
    no_teams_while_reinstating: "Invite may not specify teams while reinstating",
  }

  # Public: A facade builder for Organization::InviteStatus, enabling the
  # instantiation of new objects via an interface that's agnostic to whether
  # an email String or User instance are passed as the invitee.
  #
  # org    - an Organization instance
  # params - a Hash with the following keys
  #          invitee [required] - a String email address or User instance
  #          inviter [required] - a User instance
  #          teams - an Array
  #          role - a Symbol
  #          external_identity - an ExternalIdentity instance
  #
  # returns an Organization::InviteStatus instance or a null object
  def self.build_by_email_or_user(org, params)
    raise ArgumentError, "missing key: :invitee" unless params.key?(:invitee)
    invitee = params.delete(:invitee)

    if invitee.is_a?(User)
      new(org, invitee, **params)
    elsif User.valid_email?(invitee)
      new(org, **params.merge(email: invitee))
    else
      Organization::InvalidInviteStatus.new
    end
  end

  def initialize(org, invitee = nil, email: nil, inviter:, teams: [], role: nil, external_identity: nil)
    @organization      = org
    @invitee           = invitee
    @email             = email
    @inviter           = inviter
    @teams             = teams
    @role              = role
    @external_identity = external_identity
  end

  # Public: Get a list of errors for the proposed invitation.
  #
  # Possible errors:
  #
  # :already_on_org - The invitee can't be invited because they're already a
  #   member of the org.
  #
  # :email_already_on_org - The invitee can't be invited because there is
  #   already a member of the org with that email address.
  #
  # :invalid_teams - The invitee can't be invited because the specified teams
  #   are invalid.
  #
  # :invitee_is_not_a_user - The invitee can't be invited because they're an
  #   organization, or a bot, not a user.
  #
  # :insufficient_inviter_permissions - The inviter can't send an invitation
  #   because they have insufficient permissions.
  #
  # :invitee_and_email_provided - The invitee and email were both provided,
  #   the invite can only be delivered to one destination.
  #
  # :invitee_or_email_required - The invite doesn't have an invitee or email
  #   provided.
  #
  # :invitee_opted_out - The invitee has opted-out of receiving future
  # invitations from this organization
  #
  # :blocked_from_org - The invitee has been blocked by the organization.
  #
  # Returns an array of symbols (empty if no errors).
  def errors
    errors = []
    errors << :invalid_teams if invalid_teams?
    errors << :already_on_org if already_on_org?
    errors << :email_already_on_org if email_already_on_org?
    errors << :already_has_role if has_billing_manager_role?
    errors << :invitee_is_not_a_user if invitee && !invitee.user?
    errors << :invitee_and_email_provided if invitee.present? && email.present?
    errors << :invitee_or_email_required if invitee.nil? && email.nil?
    errors << :invalid_email if email.present? && invalid_email?
    errors << :insufficient_inviter_permissions unless sufficient_inviter_permissions?
    errors << :inviter_requires_verification if email && inviter_requires_verification?
    errors << :invitee_opted_out if OrganizationInvitation::OptOut.opted_out?(org: organization, email: email, invitee: invitee)
    errors << :blocked_from_org if blocked_from_org?
    errors << :no_teams_while_reinstating if @role == :reinstate && teams.present?
    errors
  end

  # Public: Is creating an invitation between this user, this organization, and
  # these teams valid?
  #
  # Returns a boolean.
  def valid?
    errors.empty?
  end

  # Public: Validate the proposed invitation. Raises an error if invalid.
  #
  # Returns a boolean.
  def validate!
    found_errors = errors

    if found_errors.any?
      msg = found_errors.map { |e| ERROR_MESSAGES.fetch(e, e) }.to_sentence
      raise OrganizationInvitation::InvalidError, msg
    end

    true
  end

  private

  def inviter_requires_verification?
    ContentAuthorizer.authorize(inviter, :organization_invitation, :create).has_email_verification_error?
  end

  def has_billing_manager_role?
    organization.billing_manager?(invitee) && @role == :billing_manager
  end

  def already_on_org?
    is_mgr_role = @role == :billing_manager
    organization.direct_or_team_member?(invitee) && !is_mgr_role
  end

  def email_already_on_org?
    return unless email.present?
    return if external_identity.present?
    return if @role == :billing_manager
    UserEmail.where(user_id: organization.member_ids).verified.where(email: email).any?
  end

  def sufficient_inviter_permissions?
    inviter.can_send_invitations_for?(organization, teams: teams, role: @role)
  end

  def invalid_teams?
    mismatched_teams = teams.select { |t| t.organization_id != organization.id }
    mismatched_teams.any?
  end

  def invalid_email?
    return unless email.present?
    return true if email.start_with?("mailto:")
    return true if email.ends_with?(".")
    User::EMAIL_REGEX !~ email
  end

  def blocked_from_org?
    organization.blocking?(invitee)
  end
end
