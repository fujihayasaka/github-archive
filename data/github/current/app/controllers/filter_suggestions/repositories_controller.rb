# typed: true
# frozen_string_literal: true

# ℹ️ This controller is deprecated and will soon be replaced by app/controllers/filter/repositories_controller.rb!

class FilterSuggestions::RepositoriesController < ApplicationController
  include DashboardHelper
  include FilterSuggestions::FilterSuggestionsDependency

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Repositories,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Iam,
    ApplicationRecord::Configurations

  layout false
  before_action :login_required

  MAXIMUM_REPO_LIMIT = 25

  def index
    repositories = fetch_repositories.map do |repo|
      {
        name: repo.name,
        owner: repo.owner.display_login,
        visibility: repo.visibility,
        name_with_owner: repo.name_with_display_owner,
      }
    end

    respond_payload({ repositories: repositories })
  end

  private

  # We provide repository suggestions according to the following logic:
  #   1. When no query text is provided, we suggest the user's "top repositories" (as defined by the user's activity on GitHub)
  #   2. When query text is provided, we look for matches within the top suggestions,
  #      and also within the user's own repositories that might not be in the initial set of suggestions
  #   3. If the user provides a query in the format of "owner/*", we only look for matches within the repositories owned by the specified owner
  def fetch_repositories
    query = params[:filter_value]&.downcase || ""
    top_repos = fetch_top_repositories(page: 1, per_page: MAXIMUM_REPO_LIMIT, initial_per_page: MAXIMUM_REPO_LIMIT)

    # If the query is empty, return the user's top repositories as suggestions
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

    (top_repos_matching_query + own_repos_matching_query).first(MAXIMUM_REPO_LIMIT)
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

    scope.where("name LIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(repo_name)}%").limit(MAXIMUM_REPO_LIMIT)
  end

  def resource_for_conditional_access
    :no_resource_for_conditional_access # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
  end

  def target_for_conditional_access
    current_user || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
