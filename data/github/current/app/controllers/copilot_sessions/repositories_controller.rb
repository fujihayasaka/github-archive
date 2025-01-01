# typed: true
# frozen_string_literal: true

class CopilotSessions::RepositoriesController < ApplicationController
  include Suggestions::RepositoriesDependency

  REPOSITORY_QUERY_LIMIT = 500

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Repositories,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Iam,
    ApplicationRecord::Configurations,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  # Returns repositories with an `enabled` flag for whether or not they have CCA usage enabled and the user has write permissions
  def index
    copilot_tasks_only_authorized_repos = FeatureFlag.vexi.enabled?(:copilot_tasks_only_authorized_repos, current_user, default: false)
    repos = find_repos_by_nwo(query: query_value, limit: REPOSITORY_QUERY_LIMIT, only_authorized_repos: copilot_tasks_only_authorized_repos).map do |repo|
      repo_data = format_response(repo)
      repo_data[:enabled] = repo.copilot_swe_agent_enabled_with_write_permissions?(current_user)
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

  def target_for_conditional_access
    current_user
  end
end
