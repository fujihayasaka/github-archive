# typed: true
# frozen_string_literal: true

class DependencyGraphSBOMController < AbstractRepositoryController
  before_action :check_feature_is_enabled

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::SecurityProductsEnablement,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    only: [:show]


  def show
    payload = nil
    filename = nil

    begin
      sbom_file = DependencyGraph::SBOM.get_sbom_for_repository(current_repository, ghes: GitHub.enterprise?)
      payload = sbom_file.contents
      filename = sbom_file.filename
    rescue DependencyGraph::SBOM::SBOMRequestError => e
      Failbot.report(e, app: "github-dependency-graph")
      flash[:error] = "We encountered a problem with your request. Please try again. If the problem persists, please contact support."
      return redirect_to network_dependencies_path
    rescue DependencyGraph::SBOM::SBOMTimeoutError => e
      Failbot.report(e, app: "github-dependency-graph")
      flash[:error] = "We couldn't complete your request in time. Please try again. If the problem persists, please contact support."
      return redirect_to network_dependencies_path
    end

    send_data(
      payload,
      type: :json,
      filename: filename
    )
  end

  private

  def check_feature_is_enabled
    render_404 unless current_repository.dependency_graph_enabled?
  end
end
