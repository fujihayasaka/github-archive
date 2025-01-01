# typed: false
# frozen_string_literal: true

class EditRepositories::Pages::ManagedAccessPageView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  include Repos::AccessManagementDependency

  include UrlHelper
  include ActionView::Helpers::TagHelper
  include Orgs::RolesHelper
  include MemberFeatureRequestsHelper
  include EnterpriseManagedUsersHelper
  include GitHub::Memoizer

  attr_reader :repository, :page, :direct_access_list, :repository_roles, :add_type, :organization_wide_access_list

  # Internal: maximum number of teams to show on the mixed roles warning if any
  MAX_MIXED_ROLE_TEAMS = 3

  ADMIN_PERMISSION = "admin".freeze
  WRITE_PERMISSION = "write".freeze
  READ_PERMISSION  = "read".freeze

  def organization
    return @organization if defined?(@organization)
    @organization = repository.organization
  end

  # Public: results of the direct_access_list query
  #
  # Returns an Array of Users, Teams, and RepositoryInvitations
  def direct_access_results
    direct_access_list.results
  end

  def repo_visibility
    @repo_visibility ||= repository.visibility
  end

  def repo_visibility_description
    case repo_visibility
    when Repository::PUBLIC_VISIBILITY
      "This repository is public and visible to anyone"
    when Repository::PRIVATE_VISIBILITY
      "Only those with access to this repository can view it"
    when Repository::INTERNAL_VISIBILITY
      "Members of any organization belonging to #{organization.business.safe_profile_name} can see this repository"
    end
  end

  def repo_visibility_icon
    case repo_visibility
    when Repository::PUBLIC_VISIBILITY
      "eye"
    when Repository::PRIVATE_VISIBILITY
      "eye-closed"
    when Repository::INTERNAL_VISIBILITY
      "repo"
    end
  end

  def org_owned_repo?
    return @org_owned_repo if defined?(@org_owned_repo)
    @org_owned_repo = repository.in_organization?
  end

  # Public: the direct role for the specified user over the repository.
  # It can be any of: :read, :triage, :write, :maintain, :admin
  #
  # Returns a Symbol or nil
  def direct_role_for(actor)
    repository_roles.direct_role_for(actor)
  end

  def org_member?(user)
    organization&.member?(user)
  end

  def org_owner?(user)
    organization&.admins.include?(user)
  end

  def show_individual_role_select?
    org_owned_repo?
  end

  def org_visible_base_role
    return :none unless show_org_info?
    organization.default_repository_permission
  end

  def show_collaborator_label?(member)
    if !org_member?(member)
      show_org_info? || member != current_user || current_user.site_admin?
    end
  end

  def show_individual_remove_access_button?(member)
    org_owned_repo? || member != current_user || current_user.site_admin?
  end

  # Public: Should we show a notice about the repository's owner having a
  # default repository permission?
  #
  # Returns a boolean.
  def show_default_repository_permission_notice?
    org_owned_repo? && organization.default_repository_permission != :none
  end

  def org_base_role
    org_visible_base_role.to_s.capitalize
  end

  # Public: number of members with direct access to the repo.
  # Note that org members with implicit access to the repo are not accounted here.
  # They are accounted for in base_role_description
  #
  # Returns an Integer
  def direct_access_headcount
    return @direct_access_headcount if defined?(@direct_access_headcount)
    @direct_access_headcount =
      if org_owned_repo?
        org_member_direct_grants_count + outside_collab_count + invitation_count + team_count
      else
        outside_collab_count + invitation_count
      end
  end

  # Public: headcount of org members with direct access to the repo
  #
  # Returns an Integer
  def org_member_direct_grants_count
    @org_member_count ||= repository.direct_org_member_ability_scope.count(:actor_id)
  end

  def org_access_teams
    organization&.visible_teams_for(current_user)&.size
  end

  # Public: headcount of non org members with direct access to the repo
  #
  # Returns an Integer
  def outside_collab_count
    outside_collab_count ||= repository.outside_collaborator_ability_scope.count(:actor_id)
  end

  def invitation_count
    @invitation_count ||= repository.invitees.count
  end

  # Public: headcount of teams with direct access to the repo
  #
  # Returns an Integer
  def team_count
    @team_count ||= repository.visible_teams_for(current_user).count
  end

  # Public: generate the query url for the member list filter
  #
  # - filter: a valid filter for EditRepositories#collaboration
  #
  # Returns a String
  def filter_path_for(filter)
    query = "filter:" + filter.to_s
    urls.repository_access_management_path(repository.owner, repository, query: query)
  end

  # Private: The maximum number of addable teams to show to the user. For more
  # information check out https://github.com/github/github/issues/63976#issuecomment-256671702.
  # If we add pagination or something to addable teams, this limit can be removed.
  ADDABLE_TEAM_LIMIT = 2_000

  # Public: Get all the teams that this repository can be added to by the
  # logged-in user.
  #
  # Returns an array of teams.
  def addable_teams
    @addable_teams ||= repository.addable_teams_for(current_user).limit(ADDABLE_TEAM_LIMIT)
  end

  # Public: Get all the teams that this repository is on that are visible to the
  # logged-in user.
  #
  # Returns an array of teams.
  def repository_teams
    direct_access_list.repository_teams
  end

  # Public: Should we show the add team form on page load?
  def show_add_team_form?
    addable_teams.any?
  end

  # Public: Should we show copy reminder for seat count not being changed on public repositories
  #
  # returns Boolean
  def show_public_collaborators_text?
    repository.public? && organization&.plan&.per_seat?
  end

  # Public: Should we show copy reminder for seat count being changed for private repository collaborators?
  #
  # returns Boolean
  def show_private_collaborators_text?
    repository.private? && organization&.plan&.per_seat?
  end

  # Public: Should we hide invites for outside collaborators
  def display_outside_collab_warning?
    repository.cannot_invite_outside_collaborators?(current_user) && add_type != "team"
  end

  # Public: Should we show any organization info to this user? True if:
  #     - this is an org-owned repo
  #     - user is a member of the org (not an outside collaborator)
  def show_org_info?
    org_owned_repo? && !is_user_fork_of_private_org_repo? && organization.member?(current_user)
  end

  # Public: Is this user allowed to create teams in the organization?
  def can_create_team?
    organization.can_create_team?(current_user)
  end

  def member_invitation_action
    if org_owned_repo?
      if organization.member?(current_user)
        "invite "
      else
        "search for public "
      end
    end
  end

  # Public: Should admin controls and info be shown in this view?
  #
  # Returns a boolean.
  def show_admin_stuff?
    return @show_admin_stuff if defined?(@show_admin_stuff)
    @show_admin_stuff = if repo_deny_team_changes?
      false
    else
      (repository.owner == current_user || repository.adminable_by?(current_user))
    end
  end

  def repo_deny_team_changes?
    repository.access_group_setting&.deny_team_changes?
  end

  def team_managed_by_group_settings?(team)
    return false unless team.is_a?(Team)
    repository.access_group_setting&.includes_team?(team.id)
  end

  def show_bulk_actions_toggle?(member)
    return false unless show_admin_stuff?
    show_removal_button?(member)
  end

  def show_removal_button?(member)
    !team_managed_by_group_settings?(member)
  end

  # Public: The string used to identify the member type for bulk operations
  #
  # Returns a string.
  def member_type(member)
    case member
    when User
      "user"
    when RepositoryInvitation
      "invitation"
    when Team
      "team"
    else
      raise ArgumentError, "invalid member type: #{member.class.name}"
    end
  end

  # Public: The name of the member.
  # If a profile name is available, use it.
  # If not, default to the handle.
  #
  # Returns a string.
  def member_name(member)
    case member
    when Team
      member.name
    when RepositoryInvitation
      member.invitee.present? ? member.invitee.safe_profile_name : member.email
    when User
      member.safe_profile_name
    end
  end

  # Public: the handle of the member to be shown as secondary name in the member list entry.
  # For Users, it is the handle or nil if the handle is already shown as main name for the entry.
  # For Teams, it is the slug.
  #
  # Returns a String or nil.
  def member_secondary_name(member)
    case member
    when Team
      member.combined_slug
    when RepositoryInvitation
      if member.invitee.profile_name.present?
        member.display_login
      end
    when User
      if member.profile_name.present?
        member.display_login
      end
    end
  end

  VALID_EMU_ORG_REPO_FILTERS = {
    all: "All",
    org_members: "Organization Members",
    teams: "Teams",
  }.freeze

  VALID_EMU_ORG_REPO_FILTERS_WITH_REPOSITORY_COLLABORATORS = {
    all: "All",
    org_members: "Organization Members",
    repository_collaborators: "Repository Collaborators",
    teams: "Teams",
  }.freeze

  VALID_ORG_REPO_FILTERS = {
    all: "All",
    org_members: "Organization Members",
    outside_collaborators: "Outside Collaborators",
    teams: "Teams",
    pending_invitations: "Pending Invitations",
  }.freeze

  VALID_USER_REPO_FILTERS = {
    all: "All",
    collaborators: "Collaborators",
    pending_invitations: "Pending Invitations",
  }.freeze

  # Public: Valid filters for member listing
  #
  def valid_access_filters
    if repository.is_enterprise_managed?
      if repository.organization&.business&.emu_repository_collaborators_enabled?
        VALID_EMU_ORG_REPO_FILTERS_WITH_REPOSITORY_COLLABORATORS
      else
        VALID_EMU_ORG_REPO_FILTERS
      end
    elsif show_org_info?
      VALID_ORG_REPO_FILTERS
    else
      VALID_USER_REPO_FILTERS
    end
  end

  # Public: currently selected filter.
  #
  # Returns a symbol
  def current_filter
    direct_access_list.filter
  end

  # Public: returns a descriptive name for the current filter
  def selected_access_filter_name
    valid_access_filters[current_filter] || "All"
  end

  def selected_filter?(value)
    value.to_sym == current_filter
  end

  # Is the input filter the same one as the currently selected role filter?
  # The currently selected filter is obtained from the URL.
  #
  # Returns a Boolean
  def selected_role_filter?(filter)
    selected_role_filter == filter
  end

  def has_previous_page?
    !direct_access_list.start_of_results?
  end

  def has_next_page?
    !direct_access_list.end_of_results?
  end

  def previous_page_link_params(params)
    params
      .permit(:query, :after, :before, :limit, :filter, :utf8, :user_id, :repository, :guidance_task)
      .except(:after, :guidance_task, :user_id, :repository)
      .merge(before: direct_access_list.before_cursor)
  end

  def next_page_link_params(params)
    params
      .permit(:query, :after, :before, :limit, :filter, :utf8, :user_id, :repository, :guidance_task)
      .except(:before, :guidance_task, :user_id, :repository)
      .merge(after: direct_access_list.after_cursor)
  end

  def on_per_seat_pricing?
    organization && organization.plan.per_seat? && !organization.has_unlimited_seats?
  end

  def seats_left
    organization.total_available_seats
  end

  def self_serve_billing_org?
    organization.business.present? && organization.business.can_self_serve?
  end

  # Public: the sentence containing the teams which grant the highest roles above
  # the user or team's direct role on the repository.
  #
  # Returns a String or nil
  def mixed_roles(user_or_team)
    mixed_role = repository_roles.mixed_role_for(user_or_team)
    return if mixed_role.nil?

    if mixed_role[:org_admin]
      org = repository_roles.org_giving_mixed_role(user_or_team)
      if org.present?
        "Admin as owner of the #{org.name.capitalize} organization."
      end
    elsif Ability::ACTION_RANKING.fetch(mixed_role[:team_role], 0) > Ability::ACTION_RANKING.fetch(mixed_role[:default_role], 0)
      teams = repository_roles.teams_giving_mixed_role(user_or_team).map(&:slug)

      if teams.any?
        if teams.length > MAX_MIXED_ROLE_TEAMS
          additional_team_count = teams[MAX_MIXED_ROLE_TEAMS..-1].length
          "#{mixed_role[:team_role].capitalize} via #{teams[0..MAX_MIXED_ROLE_TEAMS - 1].join(", ")} and #{additional_team_count} more #{"team".pluralize(additional_team_count)}. "
        else
          "#{mixed_role[:team_role].capitalize} via the #{teams.to_sentence} #{"team".pluralize(teams.length)}. "
        end
      end
    else
      org = repository_roles.org_giving_mixed_role(user_or_team)
      if org.present?
        "#{mixed_role[:default_role].capitalize} via #{org.name.capitalize}'s base permission."
      end
    end
  end

  def first_team_giving_mixed_role(user_or_team)
    repository_roles.teams_giving_mixed_role(user_or_team).first
  end

  # Public: placeholder for the search input field
  def search_placeholder
    if show_org_info?
      "Find people or a team"
    else
      "Find a collaborator"
    end
  end

  def show_base_role_badge?(role_name)
    org_base_role?(role_name:, organization: repository.organization)
  end

  def plan_supports_fgp?
    return false unless org_owned_repo?
    repository.organization.plan_supports?(:fine_grained_permissions)
  end

  def show_custom_roles?
    repository.owner.custom_roles_supported? && org_custom_roles.any?
  end

  def org_custom_roles
    return unless repository.owner.custom_roles_supported?
    repository.organization.custom_repo_roles
  end

  def show_role_details?
    repository.owner.custom_roles_supported? && repository.adminable_by?(current_user)
  end

  def is_org_or_repo_admin?
    repository&.organization || org_owner?(current_user)
  end

  def show_custom_roles_upsell_component?
    return unless org_owned_repo?
    return unless is_org_or_repo_admin?
    return unless eligible_for_upsell?(
      feature: MemberFeatureRequest::Feature::CustomRepositoryRoles,
      requester: current_user,
      request_entity: organization
    )
    !current_user.dismissed_notice?("vault_custom_roles")
  end

  memoize def repo_access_with_org_role_headcount
    organization_wide_access_list&.fetch("User", [])&.size || 0
  end

  memoize def repo_access_with_org_role_team_headcount
    organization_wide_access_list&.fetch("Team", [])&.size || 0
  end

  memoize def org_roles_with_repo_access
    OrganizationRole.org_roles_with_repo_access(organization)
  end

  private

  # Private: a memoized list of IDs for users that have admin access to this repository
  def admins
    @admins ||= Set.new(repository.member_ids(action: :admin))
  end

  def invitees
    @invitees ||= Set.new(invitations.map(&:invitee).map(&:id))
  end

  # Private: fetch the currently selected role filter.
  # If none is selected, :all is returned
  #
  # Returns a symbol
  def selected_role_filter
    direct_access_list.role || :all
  end

  # Private: fetch the currently selected member filter.
  # If none is selected, :all is returned
  #
  # Returns a symbol
  def selected_member_filter
    direct_access_list.filter || :all
  end
end
