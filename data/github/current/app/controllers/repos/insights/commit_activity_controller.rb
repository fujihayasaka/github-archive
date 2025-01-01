# typed: strict
# frozen_string_literal: true

class Repos::Insights::CommitActivityController < GitContentController
  before_action :enforce_plan_supports_insights
  layout "repository"

  sig { returns(String) }
  def self.react_bundle_name
    "repos-commit-activity"
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
    payload = IndexRoutePayload.new(graph_data_path: commit_activity_data_path)
    respond_with_react(
      payload: payload,
      title: "Commits · #{current_repository.name_with_display_owner}",
      layout: "layouts/repository/react_insights",
      page_data: {
        selected_link: :repo_graphs,
      },
    )
  end

  sig { void }
  def data # rubocop:todo GitHub/UseRestfulActions
    data = GitHub::RepoGraph.commit_activity_data(current_repository,
        viewer: current_user,
        cache_only: robot?)
    if data
      render json: data
    else
      head 202
    end
  rescue GitHub::RepoGraph::UnusableDataError
    render json: { unusable: true }
  end

  private

  class IndexRoutePayload < ReactPayload::Base
    sig { override.returns(String) }
    def route_id
      "commitActivityRoute"
    end

    sig { params(graph_data_path: String).void }
    def initialize(graph_data_path:)
      @graph_data_path = graph_data_path
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def payload
      {
        graphDataPath: @graph_data_path,
      }
    end
  end

  sig { params(graph_name: String).void }
  def handle_skipmc_for(graph_name)
    if GitHub.cache.skip
      GitHub::RepoGraph.clear_cache(current_repository, graph_name)
    end
  end

end
