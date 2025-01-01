# typed: true
# frozen_string_literal: true

class FilterSuggestionsController < ApplicationController
  include FilterSuggestions::FilterSuggestionsDependency

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    optional: false, only: [:users]

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    optional: false, only: [:labels, :teams]

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    optional: false, only: [:projects]

  layout false

  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  before_action :login_required

  def users # rubocop:todo GitHub/UseRestfulActions
    users = fetch_users.map do |user|
      {
        name: user.safe_profile_name,
        login: user.display_login,
        avatarUrl: user.primary_avatar_url(60),
      }
    end

    respond_payload({ users: users })
  end

  def labels # rubocop:todo GitHub/UseRestfulActions
    labels = fetch_labels.map do |label|
      {
        name: label.name,
        name_html: label.name_html,
        description: label.description,
        color: label.color
      }
    end

    respond_payload({ labels: labels })
  end

  def projects # rubocop:todo GitHub/UseRestfulActions
    projects = fetch_projects.map do |project|
      {
        title: project.title,
        value: "#{project.owner.display_login}/#{project.number}"
      }
    end

    respond_payload({ projects: projects })
  end

  def teams # rubocop:todo GitHub/UseRestfulActions
    teams = fetch_teams.map do |team|
      {
        name: team.name,
        combined_slug: team.combined_slug,
        avatar_url: team.primary_avatar_url(60),
      }
    end

    respond_payload({ teams: teams })
  end

  private

  def fetch_users
    return [current_user] if available_assignee_ids_from_sources.empty?

    scope = User
    scope = scope.preload(:profile).left_joins(:profile) if has_search_query? # We only require a left join if we're searching on the profile name
    scope = scope.where(id: available_assignee_ids_from_sources)
      .where.not(type: "Bot")

    users = if has_search_query?
      scope = scope.merge(User.where("users.login LIKE ?", "%#{sanitized_like_value}%").or(Profile.where("profiles.name LIKE ?", "%#{sanitized_like_value}%")))
      .filter_spam_for(current_user)
      .references(:profile)
      .limit(MAX_USER_QUERY_COUNT)
      scope.to_a.sort_by do |u|
        [
          u.display_login.start_with?(sanitized_like_value) ? "0" : "1",
          u.safe_profile_name.start_with?(sanitized_like_value) ? "0" : "1",
          u.display_login
        ]
      end
    else
      scope.order("users.login")
      .filter_spam_for(current_user)
      .limit(TYPE_AHEAD_RESULT_SIZE) # Since we have already sorted in SQL, just return the result size.
      .includes(:profile)
      .to_a
    end

    users.take(TYPE_AHEAD_RESULT_SIZE)
  end

  def fetch_labels
    repos = repositories_from_query.empty? ? top_repository_suggestions : repositories_from_query
    repo_ids = repos.map(&:id)
    return [] if repo_ids.empty?

    # Currently we de-dup by name, even though we can have a unique name + color across repos.
    # I believe this is OK, given the name is the important part for the search query.
    scope = Label.where(repository_id: repo_ids)

    if has_search_query?
      scope = scope.where("lowercase_name LIKE ?", "%#{sanitized_like_value.downcase}%")
    end

    scope = scope.order("name").limit(TYPE_AHEAD_RESULT_SIZE)
    Label.smart_sort(scope, false).uniq { |label| label.name.downcase }
  end

  def fetch_teams
    return [] if params[:q].nil? || params[:filter_value].nil?

    visibility_scope = T.must(current_user).async_visible_teams_for(current_user).sync
    cap_authorized_team_ids = cap_filter.authorized_resource_ids(visibility_scope)

    if params[:filter_value].include?("/")
      return filter_teams_within_org(visibility_scope).where(id: cap_authorized_team_ids)
    end

    if repositories_from_query.empty? && organizations_from_query.empty?
      filter_all_teams(visibility_scope).where(id: cap_authorized_team_ids)
    else
      filter_teams_within_query_scope.where(id: cap_authorized_team_ids)
    end
  end

  def fetch_projects
    return [] unless GitHub.projects_new_enabled? && !params_missing?

    # If there are no orgs or repos defined, we want to try give more accurate suggestions based on the top repositories
    repos = repositories_from_query.empty? && organizations_from_query.empty? ? top_repository_suggestions : repositories_from_query
    owners_from_repos = Promise.all(repos.map { |repo| repo.async_owner }).sync
    relevant_owners = (organizations_from_query + owners_from_repos).uniq
    owner_ids = relevant_owners.map(&:id)

    # We only need initial suggestions if there is no search query, pre-fetch it now to avoid a race condition in the promises.
    initial_suggestion_rankings = recently_visited_project_ids_for_owners(owner_ids)

    projects = Promise.all(
      relevant_owners.map do |owner|
        scope = owner.memex_projects.active_projects.open_projects.where("title IS NOT NULL")

        scope = if has_search_query?
          # If search query starts with '{org}/' or is a number then we want to filter by number
          project_number = sanitized_like_value
          project_number = project_number.start_with?("#{owner.display_login}/") ? project_number.split("/").last : project_number
          project_number = project_number =~ /\A\d+\z/ ? project_number : nil

          if project_number
            # Since title is a VARBINARY column, we ordinarily cannot compare a value to it using LIKE.
            # To fix that, first cast it to a UTF-8 string (whose collation is case-insensitive).
            scope.where(
              "CAST(COALESCE(title, ?) AS CHAR CHARACTER SET utf8mb4) LIKE ? OR CAST(number AS CHAR CHARACTER SET utf8mb4) LIKE ?",
              MemexProject::DEFAULT_TITLE,
              "%#{sanitized_like_value}%",
              "%#{project_number}%"
            )
          else
            # Since title is a VARBINARY column, we ordinarily cannot compare a value to it using LIKE.
            # To fix that, first cast it to a UTF-8 string (whose collation is case-insensitive).
            scope.where(
              "CAST(COALESCE(title, ?) AS CHAR CHARACTER SET utf8mb4) LIKE ?",
              MemexProject::DEFAULT_TITLE,
              "%#{sanitized_like_value}%"
            )
          end
        else
          scope.where(id: initial_suggestion_rankings)
        end

        scope = scope.limit(MEMEX_PROJECT_CAP_PER_SOURCE)
        owner.async_accessible_memexes_scope(scope, current_user)
      end
    ).sync.flatten.uniq

    sorted_projects = sort_projects(projects, owner_ids).take(TYPE_AHEAD_RESULT_SIZE)
    Promise.all(sorted_projects.map { |project| project.async_owner }).sync
    sorted_projects
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
    org_value, team_value = params[:filter_value].split("/")

    teams = T.unsafe(Team).ranked_for(current_user, scope: visibility_scope)
                .includes(:organization).where("users.display_login=?", "#{org_value}")

    teams.where("teams.slug LIKE ?", "#{team_value}%").limit(TYPE_AHEAD_RESULT_SIZE)
  end

  def filter_all_teams(visibility_scope)
    teams = T.unsafe(Team).ranked_for(current_user, scope: visibility_scope)
                .includes(:organization)

    teams.where("users.login LIKE ? OR teams.slug LIKE ?", "#{params[:filter_value]}%", "#{params[:filter_value]}%")
         .limit(TYPE_AHEAD_RESULT_SIZE)
  end

  def filter_teams_within_query_scope
    repos = repositories_from_query
    owners_from_repos = Promise.all(repos.map { |repo| repo.async_owner }).sync
    relevant_owners = (organizations_from_query + owners_from_repos).uniq.filter { |owner| owner.is_a?(Organization) }

    team_value = params[:filter_value].split("/").last
    visibility_scope = async_visible_teams_for(relevant_owners).sync
    Team.search_name_and_slug(query: team_value, scope: visibility_scope).limit(TYPE_AHEAD_RESULT_SIZE)
  end

  def sort_projects(projects, owner_ids)
    return projects if projects.empty?

    # Prioritize projects that have been visited by the current user, in order of most recently visited.
    # Then prioritize projects that start with the search query; then alphabetically as a tiebreaker.
    project_rankings = {}
    if has_search_query?
      recently_visited_project_ids_for_given_projects(projects.map(&:id))
    else
      recently_visited_project_ids_for_owners(owner_ids)
    end.each_with_index.map { |project_id, ranking| project_rankings[project_id] = ranking.to_s }

    not_visited_value = "100000" # An arbitrarily large value to use for projects that have not been visited.
    sorted_projects = projects.sort_by do |project|
      [
        project_rankings.key?(project.id) ? project_rankings[project.id] : not_visited_value,
        project.display_title.start_with?(sanitized_like_value) ? "0" : "1",
        project.display_title
      ]
    end

    sorted_projects
  end

  def recently_visited_project_ids_for_owners(owner_ids)
    return @initial_project_suggestion_ids if defined?(@initial_project_suggestion_ids)

    # If we have a search query, we will go via the `recently_visited_project_ids_for_given_projects` pathway
    return @initial_project_suggestion_ids = [] if has_search_query?
    scope = MemexProjectVisit.where(viewer_id: T.must(current_user).id)
    scope = scope.where(owner_id: owner_ids) if owner_ids.present?
    @initial_project_suggestion_ids = scope.order(last_visited_at: :desc).limit(MEMEX_PROJECT_CAP_PER_SOURCE).pluck(:memex_project_id)
  end

  def recently_visited_project_ids_for_given_projects(filter_ids)
    return @recently_visited_project_ids_for_given_projects if defined?(@recently_visited_project_ids_for_given_projects)
    return @recently_visited_project_ids_for_given_projects = [] if filter_ids.empty?

    @recently_visited_project_ids_for_given_projects = MemexProjectVisit
      .where(memex_project_id: filter_ids, viewer_id: T.must(current_user).id)
      .order(last_visited_at: :desc)
      .limit(TYPE_AHEAD_RESULT_SIZE)
      .pluck(:memex_project_id)
  end

  # It is possible that we have multiple organizations and repositories within the query
  # and we need to do a union between all possible assignee ID's
  def available_assignee_ids_from_sources # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @available_assignee_ids_from_sources if defined?(@available_assignee_ids_from_sources)

    org_ids = organizations_from_query.flat_map { |org| org.visible_user_ids_for(current_user, limit: MAX_POTENTIAL_ASSIGNEES_PER_SOURCE) }.uniq
    return @available_assignee_ids_from_sources = org_ids if org_ids.size >= MAX_POTENTIAL_ASSIGNABLE_USERS_QUERY_COUNT

    # If there are no orgs or repos defined, we want to try give more accurate suggestions based on the top repositories
    repos = repositories_from_query.empty? && org_ids.empty? ? top_repository_suggestions : repositories_from_query

    repo_ids = repos.flat_map { |repo| repo.available_assignee_ids(limit: MAX_POTENTIAL_ASSIGNEES_PER_SOURCE) }.uniq

    combined_ids = (org_ids + repo_ids)
    combined_ids = combined_ids.uniq if org_ids.size > 0 && repo_ids.size > 0 # We only need to re-call uniq if we have values in both ID arrays

    @available_assignee_ids_from_sources = combined_ids.take(MAX_POTENTIAL_ASSIGNABLE_USERS_QUERY_COUNT)
  end

  def organizations_from_query # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @organizations_from_query if defined?(@organizations_from_query)

    org_logins = values_for_filter(ORG_QUERY_SYMBOL).take(MAX_SYMBOL_QUERY_COUNT)
    return [] if org_logins.empty?

    orgs = Organization.where(login: org_logins).to_a.compact
    valid_orgs = Promise.all(orgs.map { |org| org.async_member?(current_user).then { |is_member| is_member ? org : nil } }).sync.compact

    @organizations_from_query = cap_filter.authorized_resources(valid_orgs)
  end

  def top_repository_suggestions
    TopRepositories.for(viewer: current_user, since: 1.year.ago, cap_filter: cap_filter).limit(TOP_REPOSITORIES_SIZE).to_a
  end

  def params_missing?
    params[:q].nil? || params[:filter_value].nil?
  end

  def has_search_query?
    sanitized_like_value.present?
  end

  def sanitized_like_value # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @sanitized_like_query ||= ActiveRecord::Base.sanitize_sql_like(params[:filter_value]&.to_s&.strip || "") || ""
  end
end
