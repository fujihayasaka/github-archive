# typed: true
# frozen_string_literal: true

class Orgs::Teams::TeamView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  include UrlHelper
  include GitHub::Memoizer
  attr_reader :parent_team_slug, :indent_level, :show_bulk_actions, :graphql_team, :team, :organization, :member_ids

  MAX_MEMBER_AVATAR_COUNT = 8

  def checkbox_indent
    level = indent_level.to_i
    "indent-#{level}" if level > 0
  end

  def avatar_range
    case indent_level
    when nil then 0..7
    when 0..2 then 0..7
    when 3..5 then 0..5
    when 6..8 then 0..3
    when 9..11 then 0..1
    else nil
    end
  end

  def avatar_width
    case indent_level
    when nil then "width-0"
    when 0..2 then "width-0"
    when 3..5 then "width-1"
    when 6..8 then "width-2"
    when 9..11 then "width-3"
    else nil
    end
  end

  def parent_team_class
    if child_team?
      "js-child-team color-bg-subtle"
    else #parent team
      "root-team"
    end
  end

  def team_avatar_class
    "shortened-teams-avatars"
  end

  def bg_color_class
    if child_team?
      "color-bg-subtle"
    else
      ""
    end
  end

  def child_team?
    parent_team_slug.present?
  end

  def show_bulk_actions?
    !!show_bulk_actions
  end

  def members
    # Using slice is less efficient then limit, but sufficiently large member_ids (EpicGames) can choke out SQL.
    @members ||= User.where(id: member_ids.slice(0, MAX_MEMBER_AVATAR_COUNT))
  end

  def show_external_group?
    return false unless organization.scim_managed_enterprise?
    return false unless team.externally_managed?

    # only enterprise owners have access to the IdP groups page
    organization.business.owner? current_user
  end

  def organization_roles_count
    UserRole.where(
      target_type: "Organization", target_id: organization.id,
      actor_type: "Team", actor_id: team.id,
      role: OrganizationRole.visible_roles(organization)
    ).count
  end

  # Public: Should display custom organization roles?
  #
  # Returns a boolean.
  def show_org_role_assignment_counts?
    organization.adminable_by?(current_user)
  end

  def organization_roles_link
    urls.team_organization_role_path(team, organization)
  end

  def show_enterprise_label?
    team.enterprise_team_managed?
  end

  memoize def is_enterprise_teams_org_assignment_enabled?
    team.business&.erp_feature_enabled?(:enterprise_teams_org_assignment)
  end

  memoize def show_enterprise_label_v2?
    team.business_team? && is_enterprise_teams_org_assignment_enabled?
  end
end
