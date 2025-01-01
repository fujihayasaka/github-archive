# typed: true
# frozen_string_literal: true

class Orgs::Invitations::EditPageView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :organization, :invitee, :existing_invitation, :page, :selected_team, :team_ids, :role, :query

  TEAM_SUGGESTIONS_PAGE_SIZE = 10

  # Public: Determines if the query is an email when there are no user results
  # and it matches the user email regex.
  #
  # Returns true if an email, false if not.
  def email_invitation?
    User.valid_email?(invitee)
  end

  def invitee_name
    email_invitation? ? invitee : invitee.safe_profile_name
  end

  def editing?
    existing_invitation.present?
  end

  def form_method
    editing? ? "put" : "post"
  end

  def submit_button_text
    if GitHub.bypass_org_invites_enabled? || enterprise_managed_user_enabled?
      "Add member"
    else
      if editing?
        "Update invitation"
      else
        "Send invitation"
      end
    end
  end

  def submit_button_disable_with_text
    if GitHub.bypass_org_invites_enabled? || enterprise_managed_user_enabled?
      "Adding member&hellip;"
    else
      if editing?
        "Updating invitation&hellip;"
      else
        "Sending invitation&hellip;"
      end
    end
  end

  def add_or_invite_action_word
    if GitHub.bypass_org_invites_enabled? || enterprise_managed_user_enabled?
      "Add"
    else
      "Invite"
    end
  end

  def form_path
    if editing?
      if email_invitation?
        urls.org_email_invitation_path(organization, email: invitee)
      else
        urls.org_invitation_path(organization, invitee)
      end
    else
      if organization.bypass_org_invitations?
        urls.add_member_to_org_path(organization)
      else
        urls.org_invitations_path(organization)
      end
    end
  end

  def role_input_checked?(role_input)
    role_str = role_input.to_s
    if (!editing? && role_str == "direct_member") || existing_invitation.try(:reinstate?)
      role_str == "direct_member"
    else
      role_str == role
    end
  end

  def is_team_selected?(team_id)
    team_ids&.include?(team_id.to_s)
  end

  def teams
    @teams ||= begin
      teams = teams_scope

      # Start out with the invitation's existing teams if we're editing.
      if editing?
        filter_team_ids = filter_externally_managed(existing_invitation.teams).pluck(:id)
        teams = teams.select("#{Team.table_name}.*", "teams.id IN (#{filter_team_ids.join(", ")}) as selected").reorder("selected DESC, name ASC") if filter_team_ids.any?
      end

      if paginate?
        teams = teams.paginate(page: page, per_page: TEAM_SUGGESTIONS_PAGE_SIZE)
      end
      teams
    end
  end

  def selected_team_ids
    return "" unless team_ids
    team_ids.map(&:to_i).uniq.join(",")
  end

  def ldap_teams?
    teams.any? { |team| team.ldap_mapped? }
  end

  def paginate?
    teams_scope.size > TEAM_SUGGESTIONS_PAGE_SIZE
  end

  def button_text
    if organization.bypass_org_invitations?
      "Add member"
    else
      "Send invitation"
    end
  end

  def member_param_name
    if organization.bypass_org_invitations?
      "member_id"
    else
      "invitee_id"
    end
  end

  def has_seat_for?(pending_cycle: false)
    return true if enterprise_managed_user_enabled?

    is_email_invitation = email_invitation?
    # if an org has billing delegated to a business, the pending_cycle isn't considered when checking for `has_seat_for_email?` or `has_seat_for?`
    # this saves an extra, often expensive db query (license_attributor.unique_count) for orgs / businesses with many users
    has_seat_for_key =  organization.delegate_billing_to_business? ? "business_email_invitation_#{is_email_invitation}" : "org_pending_cycle_#{pending_cycle}_email_invitation_#{is_email_invitation}"
    @_has_seats_for ||= {}

    return @_has_seats_for[has_seat_for_key] unless @_has_seats_for[has_seat_for_key].nil?

    if is_email_invitation
      @_has_seats_for[has_seat_for_key] = organization.has_seat_for_email?(invitee, pending_cycle: pending_cycle)
    else
      @_has_seats_for[has_seat_for_key] = organization.has_seat_for?(invitee, pending_cycle: pending_cycle)
    end
  end

  def no_seats_left_on_pending_cycle?
    has_seat_for? && !has_seat_for?(pending_cycle: true)
  end

  def edit_invitation_path
    if email_invitation?
      urls.org_edit_email_invitation_path(organization, email: invitee)
    else
      urls.org_edit_invitation_path(organization, invitee)
    end
  end

  def member_privileges_text
    can_repo = organization.members_can_create_repositories?
    can_team = organization.members_can_create_teams?
    return unless can_repo || can_team
    text = "They can also create new "
    text += "teams" if can_team
    text += " and " if can_repo && can_team
    text += "repositories" if can_repo
    text += "."
  end

  def team_members_count(team)
    team.members_scope_count
  end

  def team_repos_count(team)
    team.repositories_scope_count
  end

  def enterprise_managed_user_enabled?
    organization.enterprise_managed_user_enabled?
  end

  def teams_search_path
    if email_invitation?
      urls.org_email_invitation_path(organization)
    else
      urls.org_edit_invitation_path(organization, invitee)
    end
  end

  private

  def teams_scope
    scope = organization.team_search_for_user(TeamSearchQuery.new(query), current_user)

    unless organization.adminable_by?(current_user)
      scope = scope.where(permission: Team::PERMISSIONS_TO_ABILITIES["admin"])
    end

    filter_externally_managed(scope)
  end

  def filter_externally_managed(teams)
    return teams.not_externally_managed if enterprise_managed_user_enabled?
    return teams unless organization.team_sync_enabled?
    tenant = organization.team_sync_tenant
    teams.where.not(id: tenant.team_group_mappings.distinct.pluck(:team_id))
  end
end
