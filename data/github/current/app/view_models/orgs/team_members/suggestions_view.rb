# typed: true
# frozen_string_literal: true

class Orgs::TeamMembers::SuggestionsView < AutocompleteView
  attr_reader :team

  # Public: Does the logged-in user have sufficient permissions to invite people
  # to this team?
  #
  # Returns a boolean.
  def can_send_invitations?
    return @can_send_invitations if defined? @can_send_invitations
    @can_send_invitations = current_user.
      can_send_invitations_for?(organization, teams: [team])
  end

  # Public: Is the specified user a member of the org?
  #
  # user - The user to check org membership for
  #
  # Returns a boolean.
  def org_member?(user)
    user.user? && org_member_ids.include?(user.id)
  end

  # Public: Is the specified user a member of the team?
  #
  # user - The user to check team membership for
  #
  # Returns a boolean.
  def team_member?(user)
    user.user? && team_member_ids.include?(user.id)
  end

  # Public: Has the specified user been invited to the team?
  #
  # user - The user to check invitation status for.
  #
  # Returns a boolean.
  def invited?(user)
    org_invitation = pending_org_invitations.
      detect { |org_inv| org_inv.invitee_id == user.id }
    org_invitation && org_invitation.includes_team?(team)
  end

  # Public: If invitations are disabled, does the user satisfy the org
  #         two-factor requirements? Will always return true
  #         if invitations are enabled.
  #
  # user - The user to check two-factor eligibility for
  #
  # Returns a boolean.
  def direct_add_two_factor_eligible?(user)
    return true unless GitHub.bypass_org_invites_enabled?
    organization.two_factor_requirement_met_by?(user)
  end

  # Public: Should the specified user's suggestion item be enabled?
  #
  # user - The user to check enabled status for.
  #
  # Returns a boolean.
  def item_enabled_for?(user)
    return false if team_member?(user)
    return false if invited?(user)
    return true if org_member?(user)
    return false if !direct_add_two_factor_eligible?(user)

    Organization::InviteStatus.new(organization, user, inviter: current_user, teams: [team]).valid?
  end

  # Public: Can the current user invite non GitHub users to the team via email?
  #
  # Note: See the AutoCompleteQuery super class for the org-level logic.
  #
  # Returns a boolean
  def allow_email_invites?
    super && organization.adminable_by?(current_user)
  end

  def owner_allowed_action
    if GitHub.bypass_org_invites_enabled?
      "Add members"
    else
      "Send invitations"
    end
  end

  # Public: Should we show the guest collaborator warning when adding guest collaborator to team?
  #
  # user - The user to check.
  #
  # Returns a boolean.
  def show_guest_collaborator_warning?(user)
    user.guest_collaborator? && item_enabled_for?(user) && !org_member?(user)
  end

  def guest_collaborator_warning_selector
    if organization.default_repository_permission == :none
      "team-guest-collaborator-warning-no-permission"
    else
      "team-guest-collaborator-warning"
    end
  end

  private

  def pending_org_invitations
    @pending_org_invitations ||= organization.pending_invitations.
      includes(:team_invitations)
  end

  def org_member_ids
    @org_member_ids ||= organization.member_ids
  end

  def team_member_ids
    @team_member_ids ||= team.member_ids
  end
end
