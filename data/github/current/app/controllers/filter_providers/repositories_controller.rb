# typed: true
# frozen_string_literal: true

class FilterProviders::RepositoriesController < FilterProvidersController
  include FilterProviders::RepositoriesDependency

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Repositories,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Iam

  def index
    repositories = find_repositories.map { |repo| format_response(repo) }
    respond_payload({ repositories: repositories })
  end

  def show
    if repo_from_query
      respond_payload(format_response(repo_from_query))
    else
      head :unprocessable_entity
    end
  end

  private

  memoize def repo_from_query
    return nil unless query_value.present? && query_value.include?("/")
    repo = Repository.with_name_with_owner(query_value)
    return repo if repo && repo.readable_by?(current_user)
    nil
  end

  # We provide repository suggestions according to the following logic:
  #   1. When no query text is provided, we suggest the user's "top repositories" (as defined by the user's activity on GitHub) for logged in users
  #   2. When query text is provided, we look for matches within the top suggestions,
  #      and also within the user's own repositories (when logged in) that might not be in the initial set of suggestions
  #   3. If the user provides a query in the format of "owner/*", we only look for matches within the repositories owned by the specified owner
  #   4. If a user is logged out, we only show them repos provided in the repo context
  #   5. If a user is logged out and there is no repo context, we return an empty list
  def find_repositories
    query = query_value&.downcase || ""
    top_repos = find_top_repositories(page: 1, per_page: maximum_result_limit, initial_per_page: maximum_result_limit)

    # If the query is empty and the user is logged out, return an empty list
    return [] if query.blank? && !logged_in?

    # If the query is empty, return the user's top repositories as suggestions if logged in
    return top_repos if query.blank?

    if query.include?("/")
      # If the query contains a "/", we can infer that the user wants to find a repository from a specific owner
      owner_login, repo_name = query.split("/")
      owner = User.find_by_login(owner_login)

      return [] if owner.nil?
      return find_repos_of_owner(owner, repo_name: repo_name)
    end

    top_repos_matching_query = top_repos.select { |repo| repo.name_with_display_owner.downcase.include?(query) }
    own_repos_matching_query = find_repos_of_owner(current_user, repo_name: query, exclude_repo_ids: top_repos.map(&:id))

    (top_repos_matching_query + own_repos_matching_query).first(maximum_result_limit)
  end

  def find_repos_of_owner(owner, repo_name: "", exclude_repo_ids: [])
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

    scope.where("name LIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(repo_name)}%").limit(maximum_result_limit)
  end

  def format_response(repo)
    {
      name: repo.name,
      owner: repo.owner.display_login,
      visibility: repo.visibility,
      nameWithOwner: repo.name_with_display_owner,
    }
  end

  def resource_for_conditional_access
    return self unless action_name == "show"
    return :no_resource_for_conditional_access if repo_from_query.nil? # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
    repo_from_query
  end

  def target_for_conditional_access
    repo_from_query&.owner || current_user || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
