# typed: true
# frozen_string_literal: true

class Orgs::Teams::IndexPageView < Orgs::OverviewView
  include UrlHelpers
  include UrlHelper
  # View model attributes
  attr_reader :organization, :page, :query, :teams

  include PlatformHelper

  def page_title
    "Teams · #{organization.display_login}"
  end

  def show_visibility_toggle?
    true
  end

  # This method is called parent_teams because it represents relative root teams
  # Relative to a team - parent_teams are that team's direct children (excludes other descendants) (Orgs::Teams::TeamsPageView#parent_teams)
  # Relative to an org - parent_teams are teams in the org that don't have parents (root teams) (Orgs::Teams::IndexPageView#parent_teams)
  alias_method :parent_teams, :teams

  def any_teams?
    organization.visible_teams_for(current_user).any?
  end

  def heading_text
    teams_count = organization.visible_teams_for(current_user).count
    teams_count_text = helpers.pluralize(teams_count, "team", "teams")
    "#{teams_count_text} in the #{organization.display_login} organization"
  end

  def search_path
    teams_path(organization)
  end

  def teams_toolbar_actions_path
    org_teams_toolbar_actions_path(organization)
  end

  def new_team_path_for_view
    new_team_path(org: organization)
  end

  def can_move_teams?
    false
  end

  def can_create_teams?
    organization.can_create_team?(current_user)
  end

  def search?
    query.present?
  end

  def is_org_admin?
    return @is_org_admin if defined? @is_org_admin
    @is_org_admin = organization.adminable_by?(current_user)
  end

  def show_admin_stuff?
    is_org_admin?
  end

  def show_bulk_actions?
    is_org_admin?
  end

  def show_import_teams_button?
    GitHub.ldap_sync_enabled? && is_org_admin?
  end

  def show_org_teams_banner?
    !any_teams? || (organization.direct_member?(current_user) && !current_user.dismissed_notice?("org_teams_banner"))
  end

  def show_disabled_child_team_button?
    false
  end

  def member_ids_for_teams
    @member_ids_for_teams ||= Team.member_ids_indexed_by_team_ids(teams.pluck(:id))
  end
end
