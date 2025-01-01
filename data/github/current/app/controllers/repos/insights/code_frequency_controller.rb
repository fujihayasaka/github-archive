# typed: strict
# frozen_string_literal: true

class Repos::Insights::CodeFrequencyController < GitContentController
  extend T::Sig

  include ReactHelper
  before_action :enforce_plan_supports_insights, only: [:index]
  layout "repository"

  sig { returns(String) }
  def self.react_bundle_name
    "repos-code-frequency"
  end

  stylesheet_bundle :insights

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

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    only: [:data]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  sig { void }
  def index # rubocop:todo GitHub/UseRestfulActions
    return render_react_app(
      payload: {
        graphDataPath: code_frequency_data_path,
        isUsingContributionInsights: is_using_contribution_insights?,
        tooLargeUrl: "#{GitHub.help_url}/repositories/viewing-activity-and-data-for-your-repository/analyzing-changes-to-a-repositorys-content"
      },
      title: "Code frequency · #{current_repository.name_with_display_owner}",
      page_data: {
        selected_link: :repo_graphs,
      },
      layout: "layouts/repository/react_insights",
      ssr: false, # disabled until this app is ready for SSR
    ) if current_user&.feature_preview_enabled?(:repos_highcharts)

    handle_skipmc_for "code-frequency"

    render "graphs/code_frequency"
  end

  sig { void }
  def data # rubocop:todo GitHub/UseRestfulActions
    if is_using_contribution_insights?
      render json: {
        tooLarge: true
      }
    elsif data = GitHub::RepoGraph.code_frequency_data(current_repository,
        viewer: current_user,
        cache_only: robot?)
      render json: data
    else
      head 202
    end
  rescue GitHub::RepoGraph::UnusableDataError
    render json: { unusable: true }
  end

  private

  sig { params(graph_name: String).void }
  def handle_skipmc_for(graph_name)
    if GitHub.cache.skip
      GitHub::RepoGraph.clear_cache(current_repository, graph_name)
    end
  end

  sig { returns(T::Boolean) }
  def is_using_contribution_insights?
    GitHub::RepoGraph.use_insights?(viewer: current_user, repository: current_repository, cache_only: robot?)
  end
end
