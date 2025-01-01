# typed: true
# frozen_string_literal: true

# This class represents whether or not an invitation with the specified
# business and invitee can be created.
#
# The core of this class is the `errors` method. Make sure to read its docs to
# understand its possible return values.
class Business::MemberInviteStatus
  attr_reader :invitee, :email, :inviter, :business, :stafftools_invite, :skip_site_admin_check, :role

  ERROR_MESSAGES = {
    already_business_admin: "Invitee is already an owner of this enterprise",
    already_business_billing_manager: "Invitee is already a billing manager of this enterprise",
    already_business_member: "Invitee is already a member of this enterprise",
    invitee_is_not_a_user: "Invitee must be a user",
    invitee_has_invalid_state: "Invitee cannot become an enterprise administrator",
    invitee_has_invalid_state_member: "Invitee cannot become an enterprise member",
    insufficient_inviter_permissions: "Inviter has insufficient permissions",
    invitee_and_email_provided: "Invite can only be delivered to either user or email",
    invitee_or_email_required: "Invite requires either user or email",
    invalid_email: "Invite must be for a valid email address",
  }

  def initialize(
    business,
    invitee = nil,
    email: nil,
    inviter:,
    role: nil,
    stafftools_invite: false,
    skip_site_admin_check: false
  )
    @business = business
    @invitee = invitee
    @email = email
    @inviter = inviter
    @role = role
    @stafftools_invite = !!stafftools_invite
    @skip_site_admin_check = !!skip_site_admin_check
  end

  # Public: Get a list of errors for the proposed invitation.
  #
  # Possible errors:
  #
  # :already_business_admin - The invitee can't be invited as an admin because
  # they're already an admin of the business.
  #
  # :already_business_billing_manager - The invitee can't be invited as a
  # billing manager because they're already a billing manager of the business.
  #
  # :already_business_member - The invitee can't be invited as a member because
  # they're already a member of the business.
  #
  # :invitee_is_not_a_user - The invitee can't be invited because they're an
  #   organization, or a bot, not a user.
  #
  # :invitee_has_invalid_state - The invitee can't be invited if they're
  #   in an invalid state such as suspended or deceased.
  #
  # :invitee_and_email_provided - The invitee and email were both provided,
  #   the invite can only be delivered to one destination.
  #
  # :invitee_or_email_required - The invite doesn't have an invitee or email
  #   provided.
  #
  # :invalid_email - The email provided is invalid.
  #
  # :insufficient_inviter_permissions - The inviter can't send an invitation
  #   because they have insufficient permissions.
  #
  # Returns an array of symbols (empty if no errors).
  def errors
    errors = []
    errors << :already_business_admin if already_business_admin?
    errors << :already_business_billing_manager if already_business_billing_manager?
    errors << :already_business_member if already_business_member?
    errors << :invitee_is_not_a_user if invitee && !invitee.user?
    errors << :invitee_has_invalid_state_member if invitee && !business.valid_administrator_state?(invitee) && role.to_sym == :unaffiliated
    errors << :invitee_has_invalid_state if invitee && !business.valid_administrator_state?(invitee) && role.to_sym != :unaffiliated
    errors << :invitee_and_email_provided if invitee.present? && email.present?
    errors << :invitee_or_email_required if invitee.nil? && email.nil?
    errors << :invalid_email if email.present? && invalid_email?
    errors << :insufficient_inviter_permissions unless sufficient_inviter_permissions?
    errors
  end

  # Public: Is creating an invitation between this user and this business valid?
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
      raise BusinessAdministratorInvitation::InvalidError, msg
    end

    true
  end

  private

  def already_business_admin?
    @role.to_sym == :owner && business.owner?(invitee)
  end

  def already_business_billing_manager?
    @role.to_sym == :billing_manager && business.billing_manager?(invitee)
  end

  def already_business_member?
    @role.to_sym == :unaffiliated && business.unaffiliated_member?(invitee)
  end

  def sufficient_inviter_permissions?
    return true if stafftools_invite && (skip_site_admin_check || inviter.site_admin?)
    return true if business.actor_can_manage_invitations?(inviter)
    return true if @role.to_sym == :billing_manager && business.billing_manager?(inviter)
    false
  end

  def invalid_email?
    return unless email.present?
    return true if email.start_with?("mailto:")
    User::EMAIL_REGEX !~ email
  end
end
