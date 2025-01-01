# typed: true
# frozen_string_literal: true

module Suggestions::RepositoriesDependency
  private

  DEFAULT_RESULT_LIMIT = 10

  # We provide repository suggestions according to the following logic:
  #   1. When no query text is provided, we suggest the user's "top repositories" (as defined by the user's activity on GitHub) for logged in users
  #   2. When query text is provided, we look for matches within the top suggestions,
  #      and also within the user's own repositories (when logged in) that might not be in the initial set of suggestions
  #   3. If the user provides a query in the format of "owner/*", we only look for matches within the repositories owned by the specified owner
  #   4. If a user is logged out, we only show them repos provided in the repo context
  #   5. If a user is logged out and there is no repo context, we return an empty list

  def repositories_payload(query: "", limit: DEFAULT_RESULT_LIMIT)
    return [] if query.blank? && !logged_in?

    repositories = find_repositories(query: query, limit: limit)
    repositories.map { |repo| format_response(repo) }
  end

  def find_repositories(query: "", limit: DEFAULT_RESULT_LIMIT)
    return find_top_repositories(per_page: limit, initial_per_page: limit) if query.blank?

    query.downcase!

    if query.include?("/")
      # If the query is in the format of "owner/*", we only look for matches within the
      # repositories owned by the specified owner

      owner_login, repo_name = query.split("/")
      owner = User.find_by_login(owner_login)

      return [] unless owner

      # If the query is in the format of "owner/" and does not have a repo name,
      # then the `repo_name` variable is `nil` So we need to fall back to an
      # empty string in that case, so that we return the most recently pushed repos for the given
      # owner. Otherwise, an error will be raised.
      find_repos_of_owner(owner, repo_name: repo_name || "", limit: limit)
    else
      # Otherwise, we look for matches within the top suggestions, as well as within the user's own
      # repositories that might not be in the initial set of suggestions

      top_repos = find_top_repositories.filter { |repo| repo.name.downcase.include?(query) }

      if logged_in?
        repos_matching_query = find_repos_of_owner(current_user,
          repo_name: query,
          exclude_repo_ids: top_repos.map(&:id),
          limit: limit
        )

        (top_repos + repos_matching_query).uniq(&:id).first(limit)
      else
        top_repos.first(limit)
      end
    end
  end

  def find_repos_of_owner(owner, repo_name: "", exclude_repo_ids: [], limit: DEFAULT_RESULT_LIMIT)
    finder = Repositories::Public.finder_for(
      owner: owner,
      viewer: current_user,
      permission: Platform::Authorization::Permission.new(viewer: current_user, origin: Platform::ORIGIN_INTERNAL),
      repo_type: "default",
      unauthorized_viewer_organization_ids: []
    )

    scope = if owner.is_a?(Organization)
      T.cast(finder, RepositoriesOrganizationFinder).filter(
        affiliations: [:owned, :direct],
        order_by: { field: :pushed_at, direction: :desc },
      )
    else
      T.cast(finder, RepositoriesFinder).filter(
        affiliations: [:owned, :direct],
        owner_affiliations: [:owned, :direct],
        order_by: { field: :pushed_at, direction: :desc },
      )
    end

    if exclude_repo_ids.any?
      scope = scope.where.not(id: exclude_repo_ids)
    end

    scope.where("name LIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(repo_name)}%").limit(limit)
  end

  def find_top_repositories(page: 1, per_page: DEFAULT_RESULT_LIMIT, initial_per_page: DEFAULT_RESULT_LIMIT)
    return [] if !logged_in?

    TopRepositories
      .for(viewer: current_user, since: 1.year.ago, cap_filter: cap_filter)
      .simple_paginate(page: page, per_page: per_page, initial_per_page: initial_per_page)
  end

  def format_response(repo)
    {
      id: repo.id,
      name: repo.name,
      owner: repo.owner.display_login,
      visibility: repo.visibility,
      nameWithOwner: repo.name_with_display_owner,
    }
  end

  # 👇 These methods are defined in ApplicationController 👇

  def current_user
    super
  end

  def logged_in?
    super
  end

  def cap_filter
    super
  end
end
