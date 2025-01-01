# typed: true
# frozen_string_literal: true

class Api::RepositoryDependencyGraphSBOM < Api::App
  include ReceiveSchemaWithOpenApi

  before do
    check_access
  end

  get "/repositories/:repository_id/dependency-graph/sbom", operation_id: "dependency-graph/export-sbom" do
    control_access :get_contents,
      resource: current_repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    response = nil
    begin
      response = repository_sbom_client.get_repository_sbom(
        repository_id: current_repo.id,
        # As of writing, SHA is not used by DG-API
        sha: current_repo.default_oid,
        repository_name: current_repo.name_with_display_owner,
        repository_license: current_repo.license&.spdx_id,
      )
    rescue DependencyGraph::BaseTwirpClient::Error => e
      deliver_error!(500, message: "Failed to generate SBOM: #{e.message}")
    rescue Faraday::TimeoutError
      deliver_error!(500, message: "Could not generate SBOM in time. Please try again.")
    end

    # This is a pretty weird case: if we get a successful message from the dependency graph API,
    # but the SBOM is nil or an empty string, we failed somewhere but it's not clear why.
    if response.payload.empty?
      deliver_error!(500, message: "Failed to generate SBOM.")
    end

    # "payload" is a JSON document, so we need to wrap it in another JSON object
    # to form the response
    deliver_raw({
      sbom: JSON.parse(response.payload)
    })
  end

  # Ensure current repo exists and dependency graph is enabled
  def check_access
    deliver_error!(404) unless current_repo
    deliver_error!(404) unless current_repo.dependency_graph_enabled?
  end

  def repository_sbom_client
    # Set the timeout to the default request timeout - 2 to allow for error handling to take place
    @repository_sbom_client ||= DependencyGraph::RepositorySBOMClient.new(
      request_timeout_seconds: GitHub.default_request_timeout - 2,
      # Disable retries based on timeout exceptions (which is the default)
      retry_options: { exceptions: [] }
    )
  end
end
