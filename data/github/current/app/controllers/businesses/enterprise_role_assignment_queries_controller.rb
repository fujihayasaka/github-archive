# typed: strict
# frozen_string_literal: true

class Businesses::EnterpriseRoleAssignmentQueriesController < Businesses::BusinessController
  include ApplicationController::VerifiedFetchDependency

  before_action :write_enterprise_roles_required
  before_action :custom_enterprise_roles_enabled

  allow_verified_fetch only: [:index]

  depends_on_clusters \
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:index]

  SEARCH_LIMIT_MAX = 5

  sig { void }
  def index
    user_relation = this_business
      .filtered_members(
        current_user,
        query: params[:query]
      )

    user_count = user_relation.count

    users = if GitHub.single_business_environment?
      user_relation.paginate(page: 1, per_page: SEARCH_LIMIT_MAX)
      .map do |user|
        {
          id: user.id,
          name: user.display_login,
          secondaryName: user.profile_name,
          avatarUrl: user.primary_avatar_url,
          type: "user"
        }
      end
    else
      user_relation.paginate(page: 1, per_page: SEARCH_LIMIT_MAX)
      .map do |user|
        {
          id: user.user_id,
          name: user.display_login,
          secondaryName: user.profile_name,
          avatarUrl: user.avatar_url,
          type: "user"
        }
      end
    end

    team_relation = this_business
      .business_teams
      .like_name(sanitized_query)

    team_count = team_relation.count

    teams = team_relation.paginate(page: 1, per_page: SEARCH_LIMIT_MAX)
      .map do |team|
        {
          id: team.id,
          name: team.name,
          secondaryName: nil,
          avatarUrl: team.primary_avatar_url,
          type: "businessteam"
        }
      end

    render status: :ok, json: { success: true, users: users, teams: teams, user_count: user_count, team_count: team_count }
  end

  private

  sig { void }
  def custom_enterprise_roles_enabled
    render_404 unless this_business.custom_enterprise_roles_supported?
  end

  sig { void }
  def write_enterprise_roles_required
    return render(status: :unauthorized, json: { success: false }) unless current_user && this_business

    render(status: :forbidden, json: { success: false }) unless Authz.domain.check_allowed(
      current_user,
      :write_enterprise_custom_enterprise_role,
      this_business,
    )
  end

  sig { returns(T.nilable(String)) }
  def sanitized_query
    ActiveRecord::Base.sanitize_sql_like(params[:query]) unless params[:query].nil?
  end
end
