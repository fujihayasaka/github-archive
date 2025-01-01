# typed: true
# frozen_string_literal: true

class FilterProviders::TeamsController < FilterProvidersController
  include FilterProviders::RepositoriesDependency
  include ConditionalAccessDependency

  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,

  def index
    if logged_in?
      teams = find_teams.map { |team| format_response(team) }
      respond_payload({ teams: teams })
    else
      head :unprocessable_entity
    end
  end

  def show
    if team_from_query
      respond_payload(format_response(team_from_query))
    else
      head :unprocessable_entity
    end
  end

  private

  def find_teams
    visibility_scope = T.must(current_user).async_visible_teams_for(current_user).sync
    cap_authorized_team_ids = cap_filter.authorized_resource_ids(visibility_scope)

    if query_value.present? && query_value.include?("/")
      return filter_teams_within_org(visibility_scope).where(id: cap_authorized_team_ids)
    end

    # TODO: Support orgs from query?
    if repositories_from_query.empty? # && organizations_from_query.empty?
      filter_all_teams(visibility_scope).where(id: cap_authorized_team_ids)
    else
      filter_teams_within_query_scope.where(id: cap_authorized_team_ids)
    end
  end

  memoize def team_from_query
    return nil unless query_value.present? && query_value.include?("/") && logged_in?
    current_user.teams.find_by_combined_slug(query_value)
  end

  def format_response(team)
    {
      name: team.name,
      combinedSlug: team.combined_slug,
      avatarUrl: team.primary_avatar_url(60),
    }
  end

  def async_visible_teams_for(org_owners)
    visible_team_ids = org_owners.map do |org|
      next if org.deleted?
      org.visible_teams_for(current_user).pluck(:id)
    end

    T.must(current_user).async_teams.then do |user_teams|
      user_teams.where(id: visible_team_ids)
    end
  end

  def filter_teams_within_org(visibility_scope)
    org_value, team_value = query_value.split("/")

    teams = T.unsafe(Team).ranked_for(current_user, scope: visibility_scope)
                .includes(:organization).where("users.display_login=?", "#{org_value}")

    teams.where("teams.slug LIKE ?", sanitize_sql_like(team_value)).limit(maximum_result_limit)
  end

  def filter_all_teams(visibility_scope)
    teams = T.unsafe(Team).ranked_for(current_user, scope: visibility_scope)
                .includes(:organization)

    teams.where("users.login LIKE ? OR teams.slug LIKE ?", like_query_value, like_query_value)
         .limit(maximum_result_limit)
  end

  def filter_teams_within_query_scope
    repos = repositories_from_query
    owners_from_repos = Promise.all(repos.map { |repo| repo.async_owner }).sync
    relevant_owners = owners_from_repos.uniq.filter { |owner| owner.is_a?(Organization) }

    team_value = query_value.split("/").last
    visibility_scope = async_visible_teams_for(relevant_owners).sync
    Team.search_name_and_slug(query: team_value, scope: visibility_scope).limit(maximum_result_limit)
  end
end
