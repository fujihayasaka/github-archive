# typed: strict
# frozen_string_literal: true

class Repos::Insights::ContributorsController < GitContentController
  before_action :enforce_plan_supports_insights
  layout "repository"

  sig { returns(String) }
  def self.react_bundle_name
    "repos-contributors-chart"
  end

  stylesheet_bundle :insights

  include GitHub::RateLimitedRequest
  rate_limit_requests \
    only: [:data],
    max: 100,
    ttl: 1.hour,
    key: :data_rate_limit_key,
    at_limit: :data_rate_limit_render

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    only: [:data]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [
      :index,
    ],
    optional: true

  sig { void }
  def index
    render_react_app(
      payload: {
        repoUrl: repository_url(current_repository),
        defaultBranch: current_repository.default_branch,
        graphDataPath: contributors_graph_data_path,
        isUsingContributionInsights: is_using_contribution_insights?,
      },
      title: "Contributors to #{current_repository.name_with_display_owner}",
      page_data: {
        selected_link: :repo_graphs
      },
      layout: "layouts/repository/react_insights",
    )
  end

  sig { void }
  def data # rubocop:todo GitHub/UseRestfulActions
    if data = GitHub::RepoGraph.contributors_data(current_repository,
        viewer: current_user,
        cache_only: robot?)
      render json: data
    else
      head 202
    end
    rescue GitHub::RepoGraph::UnusableDataError
      render status: 400, json: { unusable: true }
  end

  private

  sig { params(graph_name: String).void }
  def handle_skipmc_for(graph_name)
    if GitHub.cache.skip
      GitHub::RepoGraph.clear_cache(current_repository, graph_name)
    end
  end

  sig { returns(String) }
  def data_rate_limit_key
    "contributors-data:#{request&.remote_ip}"
  end

  sig { void }
  def data_rate_limit_render
    head 429
  end

  sig { returns(T::Boolean) }
  def is_using_contribution_insights?
    GitHub::RepoGraph.use_insights?(viewer: current_user, repository: current_repository, cache_only: robot?)
  end
end
