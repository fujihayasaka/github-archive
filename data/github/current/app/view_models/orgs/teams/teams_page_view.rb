# typed: true
# frozen_string_literal: true

class Orgs::Teams::TeamsPageView < Orgs::OverviewView
  include UrlHelpers
  include UrlHelper
  # View model attributes
  attr_reader :page, :query, :team, :organization, :teams

  def show_visibility_toggle?
    false
  end

  def page_title
    "#{team.name} · #{organization.name} Teams List"
  end

  # This method is called parent_teams because it represents relative root teams
  # Relative to a team - parent_teams are that team's direct children (excludes other descendants) (Orgs::Teams::TeamsPageView#parent_teams)
  # Relative to an org - parent_teams are teams in the org that don't have parents (root teams) (Orgs::Teams::IndexPageView#parent_teams)
  alias_method :parent_teams, :teams

  def any_teams?
    team.has_child_teams?
  end

  def heading_text
    teams_count = team.descendants.count
    "#{helpers.pluralize(teams_count, "team", "teams")} in the #{team.name} team"
  end

  def is_team_admin?
    return @is_team_admin if defined? @is_team_admin
    @is_team_admin = team.adminable_by?(current_user)
  end

  def is_org_admin?
    return @is_org_admin if defined? @is_org_admin
    @is_org_admin = organization.adminable_by?(current_user)
  end

  def show_admin_stuff?
    is_team_admin?
  end

  def show_bulk_actions?
    is_org_admin?
  end

  def show_import_teams_button?
    GitHub.ldap_sync_enabled? && is_org_admin?
  end

  def search_path
    team_teams_path(team)
  end

  def teams_toolbar_actions_path
    team_teams_toolbar_actions_path(organization, team_slug: team.slug)
  end

  def new_team_path_for_view
    "#{new_team_path(org: organization)}?parent_team=#{team.slug}"
  end

  def can_move_teams?
    is_team_admin? && team.locally_managed? && !team.secret?
  end

  def can_create_teams?
    organization.can_create_team?(current_user) && team.locally_managed? && !team.secret?
  end

  def search?
    query.present?
  end

  def show_org_teams_banner?
    !any_teams? || (organization.direct_member?(current_user) && !current_user.dismissed_notice?("org_teams_banner"))
  end

  def show_disabled_child_team_button?
    !can_create_teams? && !team.secret?
  end

  def show_pending_team_change_parent_requests?
    show_admin_stuff? && inbound_request_count > 0
  end

  def current_team_id
    team.global_relay_id
  end

  def inbound_request_count
    TeamChangeParentRequest.inbound_pending_requests_non_null_parent_initiated(team).count +
    TeamChangeParentRequest.inbound_pending_requests_non_null_child_initiated(team).count
  end

  def member_ids_for_teams
    @member_ids_for_teams ||= Team.member_ids_indexed_by_team_ids(teams.pluck(:id))
  end
end
