# typed: true
# frozen_string_literal: true

class Api::RepositoryDependencyGraphSBOM < Api::App
  include ReceiveSchemaWithOpenApi

  before do
    check_access
  end

  rate_limit_as Api::RateLimitConfiguration::DEPENDENCY_SBOM_FAMILY

  get "/repositories/:repository_id/dependency-graph/sbom", operation_id: "dependency-graph/export-sbom" do
    control_access :get_contents,
      resource: current_repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    payload = nil
    begin
      sbom_file = DependencyGraph::SBOM.get_sbom_for_repository(current_repo, ghes: GitHub.enterprise?)
      payload = sbom_file.contents
    rescue DependencyGraph::SBOM::SBOMRequestError, DependencyGraph::SBOM::SBOMTimeoutError => e
      deliver_error!(500, message: e.message)
    end

    # "payload" is a JSON document, so we need to wrap it in another JSON object
    # to form the response
    deliver_raw({
      sbom: JSON.parse(payload)
    })
  end

  # Ensure current repo exists and dependency graph is enabled
  def check_access
    deliver_error!(404) unless current_repo
    deliver_error!(404) unless current_repo.dependency_graph_enabled?
  end

  def rate_limit_status_code
    429
  end
end
