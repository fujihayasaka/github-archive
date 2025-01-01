# typed: true
# frozen_string_literal: true

class OrganizationInviter
  include UrlHelpers

  BASE_RESCUE_MESSAGE = "You can't do that at this time.".freeze
  ENTERPRISE_TEAM_MANAGED_ERROR = "You cannot invite users to organization teams managed by an enterprise team.".freeze

  class RequiresVerification < StandardError
  end

  attr_reader :invitation, :error, :return_path

  def initialize(organization, actor:, role: nil, team_ids: nil, invitee: nil, email: nil)
    @organization = organization
    @actor = actor
    @role = role
    @team_ids = team_ids
    @invitee = invitee
    @email = email&.strip
  end

  def email_invitation?
    invitee.nil? && email.present?
  end

  def invite_user
    invite_options = {
      inviter: actor,
      teams: teams,
      role: role,
      invitation_source: :member,
    }

    if User.valid_email?(email)
      invite_options[:email] = email

      # Email invites require that the actor has a verified email address.
      if email_verification_required?
        raise RequiresVerification
      end
    end

    raise OrganizationInvitation::InvalidError if actor.spammy?

    return false unless has_seat_for_invitee?

    # Do not allow inviting users to enterprise managed organization teams
    if teams.any?(&:enterprise_team_managed?)

      @error = ENTERPRISE_TEAM_MANAGED_ERROR
      @return_path = org_edit_invitation_path(organization, invitee.display_login)
      return false
    end

    organization.transaction do
      @invitation = organization.invite(invitee, **invite_options)
      true
    end
  rescue OrganizationInvitation::AlreadyAcceptedError, OrganizationInvitation::InvalidError, ActiveRecord::RecordInvalid
    @error = BASE_RESCUE_MESSAGE
    if invitee.blank?
      @return_path = org_edit_email_invitation_path(organization, email: email)
    else
      @return_path = org_edit_invitation_path(organization, invitee.display_login)
    end
    false
  rescue ::OrganizationInvitation::TradeControlsError
    @error = TradeControls::Notices.notice_as_plaintext(:org_invite_restricted)
    @return_path = org_edit_email_invitation_path(organization, email: email)
    false
  end

  def missing_seat_return_path
    if invitee.blank?
      org_edit_email_invitation_path(organization, email: email)
    else
      org_edit_invitation_path(organization, invitee.display_login)
    end
  end

  private

  attr_reader :organization, :actor, :role, :team_ids, :invitee, :email, :volume_licensing

  def teams
    @_teams ||= if role == "reinstate" || team_ids.blank?
      []
    else
      organization.teams.where(id: team_ids)
    end
  end

  def email_verification_required?
    authorization = ContentAuthorizer.authorize(
      actor, :organization_invitation, :create
    )

    authorization.has_email_verification_error?
  end

  def has_seat_for_invitee?
    if organization.business.present? && organization.business.has_sufficient_licenses_for?(user: invitee, email: email)
      true
    elsif !organization.has_seat_for?(invitee)
      @error = if organization.owned_by_metered_plan_trial_business?
        "You need to activate your enterprise subscription to invite a new person to #{organization.safe_profile_name}."
      else
        "You need to purchase at least one additional seat to invite a new person to #{organization.safe_profile_name}."
      end
      @return_path = missing_seat_return_path
      false
    elsif !organization.has_seat_for?(invitee, pending_cycle: true)
      @error = "You must cancel your pending seats downgrade to invite a new person to #{organization.safe_profile_name}."
      @return_path = missing_seat_return_path
      false
    else
      true
    end
  end
end
