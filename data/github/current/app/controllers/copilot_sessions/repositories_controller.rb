# typed: true
# frozen_string_literal: true

class CopilotSessions::RepositoriesController < ApplicationController
  include Suggestions::RepositoriesDependency

  REPOSITORY_QUERY_LIMIT = 10

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Repositories,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Iam,
    ApplicationRecord::Configurations,
    ApplicationRecord::Profiles,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  # Returns repositories with an `enabled` flag for whether or not they have CCA usage enabled and the user has
  # write permissions.
  def index
    repo_results = find_repos_by_nwo(
      query: query_value,
      limit: REPOSITORY_QUERY_LIMIT,
      only_authorized_repos: true,
      default_owner: default_owner_value,
      include_in_top_repos: include_in_top_repos_value
    )
    # The format_response of the repo object below causes a query for the
    # default_branch of each repo which in turn causes a serial Spokes API call
    # to each repo. We use IOPromise here to preload all of the required API
    # calls first, then rely on the per-repo memoization of the default branch
    # to instantly answer the questions during the serialization below.
    Promise.all(repo_results.map(&:async_default_branch)).sync
    enabled_repos = Promise.all(repo_results.map { |repo| repo.async_copilot_swe_agent_enabled_with_write_permissions?(current_user) }).sync
    repos = repo_results.each_with_index.map do |repo, index|
      repo_data = format_response(repo)
      repo_data[:enabled] = enabled_repos[index]

      repo_data
    end

    respond_to do |format|
      format.json do
        render json: {
          repositories: repos
        }
      end
    end
  end

  private

  def query_value
    params[:q].to_s
  end

  def default_owner_value
    params[:defaultOwner].to_s.presence
  end

  def include_in_top_repos_value
    params[:includeInTopRepos].to_s.presence
  end

  def target_for_conditional_access
    current_user
  end
end
