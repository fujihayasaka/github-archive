# typed: true
# frozen_string_literal: true

class DependencyGraphSBOMController < AbstractRepositoryController
  before_action :login_required
  before_action :check_feature_is_enabled

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    only: [:show]


  def show
    response = nil
    begin
      response = repository_sbom_client.get_repository_sbom(
        repository_id: current_repository.id,
        sha: current_repository.default_oid,
        repository_name: current_repository.name_with_display_owner,
        repository_license: current_repository.license&.spdx_id,
      )
    rescue DependencyGraph::BaseTwirpClient::Error, Faraday::TimeoutError => e
      Failbot.report(e, app: "github-dependency-graph")
      flash[:error] = "We couldn't complete your request in time. Please try again. If the problem persists, please contact support."
      return redirect_to network_dependencies_path
    end

    if response.payload.empty?
      flash[:error] = "We encountered a problem with your request. Please try again. If the problem persists, please contact support."
      return redirect_to network_dependencies_path
    end

    send_data(
      response.payload,
      type: :json,
      filename: "#{current_repository.name}_#{current_repository.owner}_#{current_repository.default_oid}.json"
    )
  end

  private

  def check_feature_is_enabled
    return render_404 unless current_repository.dependency_graph_enabled?
  end

  memoize def repository_sbom_client
    # Since this client will be running inside the scope of a client request, we need to make sure it
    # times out with enough time to trigger the handler.
    DependencyGraph::RepositorySBOMClient.new(
      request_timeout_seconds: GitHub.default_request_timeout - 2,
      # By default Faraday will retry on timeout exceptions, but we want to handle timeouts ourselves
      retry_options: {
        exceptions: []
      }
    )
  end
end
