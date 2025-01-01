# typed: true
# frozen_string_literal: true

# Exposes predicate methods that respond to queries about a given organization
# invitation request. Used by Orgs::InvitationsController#edit to render the
# appropriate template.
class OrganizationInvitationRequest
  attr_reader :current_user, :invitation, :invitation_status, :invitee,
    :organization, :start_fresh, :restorable_organization_user

  def initialize(email:, login:, organization:, current_user:, start_fresh:)
    @organization = organization
    @current_user = current_user
    @start_fresh = start_fresh
    @invitee = find_invitee(email, login)
    @invitation = find_invitation
    @invitation_status = find_invitation_status
    @restorable_organization_user = find_restorable_record
  end

  # Public: Is creating an invitation between this user, this organization, and
  # these teams invalid? (see: InviteStatus)
  def invalid?
    !invitation_status.valid?
  end

  # Public: Is creating an invitation between this user, this organization, and
  # these teams valid?
  def reinstating_membership?
    start_fresh.blank? && !!restorable_organization_user.try(:restorable?)
  end

  # Public: Are we inviting a non-GitHub user by their email address?
  def inviting_by_email?
    invitee.is_a?(String)
  end

  # Public: Returns a hash containing the invitation request's attributes. Used
  # to pass local variables to render methods.
  def to_h
    {}.tap do |attr|
      attr[:organization] = organization
      attr[:invitee] = invitee
      attr[:existing_invitation] = invitation
      attr[:status] = invitation_status
      attr[:restorable_organization_user] = restorable_organization_user
    end
  end

  private

  # Private: Finds the invitation request invitee
  #
  # NB: #find_by_login! is used because when #find_invitee is called from a
  # controller, ActiveRecord::RecordNotFound is handled by ApplicationController
  def find_invitee(email, login)
    if User.valid_email?(email)
      email
    elsif login.present?
      User.find_by!(login: login)
    end
  end

  def find_invitation
    if inviting_by_email?
      organization.pending_invitation_for(email: invitee)
    else
      organization.pending_invitation_for(invitee, include_private_emails: false)
    end
  end

  def find_invitation_status
    Organization::InviteStatus.build_by_email_or_user(
      organization,
      invitee: invitee,
      inviter: current_user,
    )
  end

  def find_restorable_record
    return if inviting_by_email? || invalid?
    Restorable::OrganizationUser.restorable(organization, invitee)
  end
end
