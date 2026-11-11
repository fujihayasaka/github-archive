# typed: true
# frozen_string_literal: true

class Api::RepositoryDependencyGraphSBOM < Api::App
  include ReceiveSchemaWithOpenApi

  before do
    check_access
  end

  # For now, we use a linear 1 second retry-after as SBOM generation typically
  # won't be within millisecond latency for non-trivial repositories.
  POLL_INTERVAL_SECONDS = 1
  rate_limit_as Api::RateLimitConfiguration::DEPENDENCY_SBOM_FAMILY

  # Synchronously request the SBOM for the repository's default branch at call time
  get "/repositories/:repository_id/dependency-graph/sbom", operation_id: "dependency-graph/export-sbom" do
    unless GitHub.enterprise?
      deprecated(
        deprecation_date: Time.utc(2026, 5, 12),
        sunset_date: Time.utc(2026, 11, 13),
        info_url: "https://github.blog/changelog/2026-05-12-synchronous-sbom-api-deprecated",
        alternate_path_url: "/repos/#{current_repo.name_with_display_owner}/dependency-graph/sbom/generate-report"
      )
    end

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

  # Request the generation of an SBOM report for the repository
  #
  # This returns a URL to poll for your report pointed at the `dependency-graph/fetch-sbom-report` operation
  #
  # For now, this only supports the default branch at request time, but it should be the basis for:
  # - Generating SBOMs filtered to single manifest paths(s)
  # - Generating SBOMs from non-default branches when we support tracking multiple graphs
  # - Retrieving SBOMs for artefacts attached to this repository
  get "/repositories/:repository_id/dependency-graph/sbom/generate-report", operation_id: "dependency-graph/generate-sbom-report", read_from_replicas: true do
    deliver_error!(404) if GitHub.enterprise?

    control_access :get_contents,
      resource: current_repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    report_manager = DependencyGraph::SBOM::ReportManager.new(repo: current_repo, user: current_user)

    sbom_uuid = nil
    begin
      sbom_uuid = report_manager.generate_sbom
    rescue DependencyGraph::SBOM::SBOMRequestError, DependencyGraph::SBOM::SBOMTimeoutError => e
      deliver_error!(500, message: e.message)
    end

    sbom_url = api_url("/repos/#{current_repo.name_with_display_owner}/dependency-graph/sbom/fetch-report/#{sbom_uuid}")

    deliver_raw({ sbom_url: sbom_url }, status: 201)
  end

  # Fetch an SBOM report by UUID
  #
  # Returns 202 while processing and 302 redirect to the SBOM download URL when complete.
  get "/repositories/:repository_id/dependency-graph/sbom/fetch-report/:sbom_uuid", operation_id: "dependency-graph/fetch-sbom-report" do
    deliver_error!(404) if GitHub.enterprise?

    control_access :get_contents,
      resource: current_repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    report_manager = DependencyGraph::SBOM::ReportManager.new(repo: current_repo, user: current_user)

    result = nil
    begin
      result = report_manager.fetch_sbom(sbom_uuid: params[:sbom_uuid])
    rescue DependencyGraph::SBOM::SBOMNotFoundError
      deliver_error!(404, message: "SBOM report not found or has expired.")
    rescue DependencyGraph::SBOM::SBOMRequestError, DependencyGraph::SBOM::SBOMTimeoutError => e
      deliver_error!(500, message: e.message)
    end

    case result.status
    when :JOB_STATUS_COMPLETED
      deliver_empty(url: result.sbom_url, status: 302)
    when :JOB_STATUS_PROCESSING
      headers["Retry-After"] = POLL_INTERVAL_SECONDS
      deliver_empty status: 202
    when :JOB_STATUS_FAILED, :JOB_STATUS_BLOCKED
      deliver_error!(500, message: result.user_error_message || "SBOM generation failed.")
    else
      deliver_error!(500, message: "SBOM generation returned an unexpected status.")
    end
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
