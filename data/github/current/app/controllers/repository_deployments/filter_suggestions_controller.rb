# typed: true
# frozen_string_literal: true

class RepositoryDeployments::FilterSuggestionsController < ApplicationController
  include FilterSuggestions::FilterSuggestionsDependency
  include FilterProviders::RepositoriesDependency
  include RepositoryControllerMethods

  map_to_service :deployments # rubocop:todo GitHub/MapToService

  depends_on_clusters ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Spokes,
    ApplicationRecord::ActionsEnvironments,
    optional: false, only: [:users, :environments, :refs]

  # Limit the amount of symbols we query for to reduce abuse possibility.
  USER_QUERY_LIMIT = 1000
  MAXIMUM_RESULT_LIMIT = 10

  layout false

  before_action :login_required

  def users # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless current_user_can_see_deployments?
    respond_payload({
      users: fetch_users.map { |user| format_user_response(user) }
    })
  end

  def environments # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless current_user_can_see_deployments?
    respond_payload({
      environments: fetch_environments
    })
  end

  def refs # rubocop: todo GitHub/UseRestfulActions
    return render_404 unless current_user_can_see_deployments?
    refs = fetch_refs.map do |ref|
      {
        ref: ref
      }
    end

    respond_payload({ refs: refs })
  end

  private

  memoize def current_user_can_see_deployments?
    current_repository.present? &&
      # There must be 1+ existing Deployments in the repository for this check to pass
      current_repository.can_see_deployments?(current_user)
  end

  def fetch_users
    # Start by casting a wide net WITHOUT FILTERING to gather potential user IDs. Again, this does NOT take any
    # potential filter query value into account yet.
    user_ids_from_deployments = fetch_deployment_creator_ids
    user_ids_from_repo = current_repository.available_assignee_ids(limit: USER_QUERY_LIMIT)
    potential_user_ids = user_ids_from_deployments | user_ids_from_repo

    return [current_user] if potential_user_ids.empty?

    scope = User.where(id: potential_user_ids)

    users = []

    if has_search_query?
      scope = scope.like_login_or_profile_name(filter_value_query)
        .filter_spam_for(current_user)
        .limit(USER_QUERY_LIMIT)

      users = scope.to_a.sort_by do |u|
        username_lower = u.display_login.downcase
        [
          # Give top preference to exact matches
          username_lower == sanitized_like_value ? "0" : "1",
          username_lower.start_with?(sanitized_like_value) ? "0" : "1",
          u.safe_profile_name.downcase.start_with?(sanitized_like_value) ? "0" : "1",
          # Give a slight preference to users who have definitely created deployments in the past
          user_ids_from_deployments.include?(u.id) ? "0" : "1",
          u.display_login
        ]
      end
    else
      users = scope.order("users.login")
        .filter_spam_for(current_user)
        .limit(MAXIMUM_RESULT_LIMIT)
        .includes(:profile)
        .to_a
    end

    users.take(MAXIMUM_RESULT_LIMIT)
  end

  # This has the potential to miss desirable matches, especially if there are a lot of deployment creators and the
  # relevant user no longer as access to the repository. This can be exacerbated if the viewer is attempting to filter
  # suggestions based on the user's real/display name rather than just their username. This is a known limitation of
  # the current implementation.
  def fetch_deployment_creator_ids
    sql = Arel.sql(<<-SQL, repo_id: current_repository.id)
      SELECT DISTINCT creator_id
      FROM deployments
      WHERE repository_id = :repo_id
      ORDER BY created_at DESC
      LIMIT #{USER_QUERY_LIMIT}
    SQL
    Deployment.connection.select_values(sql)
  end

  def format_user_response(user)
    {
      name: user.safe_profile_name,
      login: user.display_login,
      avatarUrl: user.primary_avatar_url(60),
    }
  end

  def fetch_environments
    actions_environments = fetch_actions_environments
    deployment_environments = fetch_deployment_environments

    # Prefer currently existing Actions environment names (i.e. casing) when there are duplicates
    environments = actions_environments + deployment_environments
    environments = environments.uniq { |env| env[:name].downcase }

    if has_search_query?
      lower_deployment_environment_names = deployment_environments.map { |env| env[:name].downcase }

      # Sort the list so that any environment (within the query's MAXIMUM_RESULT_LIMIT limit, anyway) with an exactly
      # matching or partially matching name will be presented earlier among the results
      environments = environments.sort_by do |env|
        env_lower_name = env[:name].downcase
        [
          # Give top preference to exact matches
          env_lower_name == sanitized_like_value ? "0" : "1",
          env_lower_name.start_with?(sanitized_like_value) ? "0" : "1",
          # Give a slight preference to environments that have definitely received deployments in the past
          lower_deployment_environment_names.include?(env_lower_name) ? "0" : "1",
          env[:name]
        ]
      end
    end

    # Finally, limit to the first MAXIMUM_RESULT_LIMIT environments after combining and sorting
    environments.take(MAXIMUM_RESULT_LIMIT)
  end

  def fetch_deployment_environments
    return [] if current_repository.nil?

    results = []

    # Unique by environment name. This may need to be revised/removed in the future if we need to present
    # different options or additional column values per [more than one] repo
    sql = Arel.sql(<<-SQL, repo_id: current_repository.id)
      SELECT DISTINCT latest_environment
      FROM deployments
      WHERE repository_id = :repo_id
    SQL

    if has_search_query?
      env_name_like = "%#{sanitized_like_value}%"
      sql += Arel.sql(<<-SQL, env_match: env_name_like)
          AND latest_environment LIKE :env_match
      SQL
    end

    sql += Arel.sql(<<-SQL)
      ORDER BY created_at DESC
      LIMIT #{MAXIMUM_RESULT_LIMIT}
    SQL

    fuzzy_environment_names = Deployment.connection.select_values(sql)

    if has_search_query?
      unless fuzzy_environment_names.map(&:downcase).include?(sanitized_like_value)
        # Ensure exact match will be returned if existing
        exact_environment_name = current_repository.deployments.where(latest_environment: sanitized_like_value).limit(1).pluck(:latest_environment)
        results += exact_environment_name
      end
    end

    # Add the fuzzy matches
    results += fuzzy_environment_names

    results.map do |env_name|
      {
        "name": env_name
      }
    end
  end

  def fetch_actions_environments
    return [] if current_repository.nil?

    results = []

    repo_id = current_repository.id
    scope = Environment.where(repository_id: repo_id)

    if has_search_query?
      scope = scope.where("name LIKE ?", "%#{sanitized_like_value}%")
    end

    # Unique by name. This may need to be revised/removed in the future if we need to present
    # different options or additional column values per [more than one] repo
    scope = scope.group("name")

    scope = scope.order(name: :asc).limit(MAXIMUM_RESULT_LIMIT)
    fuzzy_environments = scope.to_a

    if has_search_query?
      unless fuzzy_environments.map(&:name).map(&:downcase).include?(sanitized_like_value)
        # Ensure exact match will be returned if existing
        exact_environment = current_repository.environments.where(name: sanitized_like_value).limit(1)
        results += exact_environment
      end
    end

    # Add the fuzzy matches
    results += fuzzy_environments

    results.map do |env|
      {
        "name": env.name
      }
    end
  end

  def fetch_refs
    return [] if current_repository.nil?

    results = []

    sql = Arel.sql(<<-SQL, repo_id: current_repository.id)
      SELECT DISTINCT ref
      FROM deployments
      WHERE repository_id = :repo_id
    SQL

    if has_search_query?
      sql += Arel.sql(<<-SQL, ref_match: "%#{sanitized_like_value}%")
        AND ref LIKE :ref_match
      SQL
    end

    sql += Arel.sql(<<-SQL)
      ORDER BY created_at DESC
      LIMIT #{MAXIMUM_RESULT_LIMIT}
    SQL

    fuzzy_refs = Deployment.connection.select_values(sql)

    if has_search_query?
      unless fuzzy_refs.include?(sanitized_like_value)
        # Ensure exact match will be returned if existing
        exact_ref = current_repository.deployments.where(ref: sanitized_like_value).limit(1).pluck(:ref)
        results += exact_ref
      end
    end

    # Add the fuzzy matches
    results += fuzzy_refs

    results = results.uniq.sort_by do |ref|
      ref_lower = ref.downcase
      [
        # Give top preference to exact matches
        ref_lower == sanitized_like_value ? "0" : "1",
        ref_lower.start_with?(sanitized_like_value) ? "0" : "1",
        ref
      ]
    end
    results.take(MAXIMUM_RESULT_LIMIT)
  end

  memoize def filter_value_query
    params[:filter_value]&.to_s&.strip&.downcase || ""
  end

  memoize def sanitized_like_value
    ActiveRecord::Base.sanitize_sql_like(filter_value_query) || ""
  end

  memoize def has_search_query?
    sanitized_like_value.present?
  end
end
