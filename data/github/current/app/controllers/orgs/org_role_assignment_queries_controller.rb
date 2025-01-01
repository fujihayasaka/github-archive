# typed: strict
# frozen_string_literal: true

class Orgs::OrgRoleAssignmentQueriesController < Orgs::Controller
  include BaseHelpers::Helpers

  before_action :login_required
  before_action :write_org_roles_required
  before_action :ensure_trade_restrictions_allows_org_settings_access
  before_action :ensure_enterprise_teams_org_roles_supported

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Configurations

  SEARCH_LIMIT_MAX = 5

  sig { void }
  def index
    query = params[:query] || ""

    user_relation = current_organization
      .members
      .like_login_or_profile_name(query) # scope sanitizes query
    user_count = user_relation.count

    users = user_relation
      .paginate(page: 1, per_page: SEARCH_LIMIT_MAX)
      .map do |user|
        {
          id: user.id,
          name: user.display_login,
          secondaryName: user.profile_name,
          avatarUrl: user.primary_avatar_url,
          type: "user"
        }
      end

    # scope does not sanitize query
    sanitized_query = ActiveRecord::Base.sanitize_sql_like(query)
    team_relation = current_organization
      .teams_with_business_teams
      .like_name(sanitized_query)
    team_count = team_relation.count

    teams = team_relation
      .paginate(page: 1, per_page: SEARCH_LIMIT_MAX)
      .map do |team|
        {
          id: team.id,
          name: team.name,
          secondaryName: nil,
          avatarUrl: team.primary_avatar_url,
          type: team.class.name.downcase
        }
      end

    render status: :ok, json: { success: true, users: users, teams: teams, user_count: user_count, team_count: team_count }
  end

  private

  sig { void }
  def write_org_roles_required
    return render(status: :unauthorized, json: { success: false }) unless current_user && current_organization

    render(status: :not_found, json: { success: false }) unless Authz.domain.check_allowed(
      current_user,
      :write_organization_custom_org_role,
      current_organization,
    )
  end

  sig { void }
  def ensure_enterprise_teams_org_roles_supported
    render_404 unless current_organization.business&.enterprise_teams_org_roles_supported?
  end
end
