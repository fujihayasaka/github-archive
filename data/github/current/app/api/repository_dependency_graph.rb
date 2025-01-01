# typed: true
# frozen_string_literal: true
require "date"
require "dependency_snapshot"
require "dependency_graph/repository_dependencies_provider"

class Api::RepositoryDependencyGraph < Api::App
  include FeatureFlagHelper

  rate_limit_as Api::RateLimitConfiguration::DEPENDENCY_SNAPSHOTS_FAMILY

  before do
    @accepted_scopes = [:repo]
  end

  def ip_allowlist_enforceable
    return :no if hmac_authenticated_internal_service_request?
    :yes
  end

  def dependency_snapshots_enabled?
    current_repo.dependency_graph_enabled? && (!GitHub.enterprise? || ENV.fetch("DEPENDENCY_SNAPSHOTS_ENABLED", "0") == "1")
  end

  # Create a new snapshot
  post "/repositories/:repository_id/dependency-graph/snapshots", operation_id: "dependency-graph/create-repository-snapshot" do
    # hidden API, we will eventually document it here
    # @documentation_url = "/rest/reference/repos#create-a-snapshot"

    repo = current_repo
    control_access :create_snapshot,
      resource: repo,
      repo: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    return deliver_error 404, message: "The Dependency graph is disabled for this repository. Please enable it before submitting snapshots." unless dependency_snapshots_enabled?

    # hydrated JSON request body, shape-validated, as a hash
    data = receive_with_openapi

    data["scanned"] = DateTime.parse(data["scanned"]) if data["scanned"].present?

    output = dependency_snapshot_provider.create_dependency_snapshot(
      repository: repo,
      req_body: data,
    )

    if output[:errors].blank? && output[:response].present?
      if output[:status_code].between?(200, 299)
        DependencySnapshotCompletedJob.perform_later(repo.id, data["sha"])
      end
      deliver :repository_snapshot_create_hash, output[:response], status: output[:status_code]
    else
      deliver_snapshot_error output
    end
  end

  # Get snapshot
  get "/repositories/:repository_id/dependency-graph/snapshots/:snapshot_id", operation_id: :internal do
    @route_owner = "@github/dependency-graph"
    # hidden API, we will eventually document it here
    # @documentation_url = "/rest/reference/repos#get-snapshot"

    return deliver_error 404 unless dependency_snapshots_enabled?

    repo = current_repo
    control_access :get_snapshot,
      resource: repo,
      repo: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    output = dependency_snapshot_provider.get_dependency_snapshot(
      repository: repo,
      snapshot_id: int_id_param!(key: :snapshot_id),
    )

    if output[:errors].blank? && output[:response].present?
      return deliver :repository_snapshot_hash, output[:response], status: output[:status_code]
    else
      deliver_snapshot_error output
    end
  end

  # Get dependencies for a repository
  get "/repositories/:repository_id/dependency-graph/dependencies", operation_id: "dependency-graph/get-snapshot-dependencies-for-repo" do
    @route_owner = "@github/dependency-graph"
    # currently undocumented and unsupported API, we will eventually document it here:
    # @documentation_url = "/rest/dependency-graph/dependency-submission#get-snapshot-dependencies-for-a-repository"

    return deliver_error 404 unless dependency_snapshots_enabled?
    return deliver_error 404 unless GitHub.flipper[:dependency_graph_experimental_dependencies_endpoint].enabled?

    repo = current_repo
    ref = "refs/heads/#{current_repo.default_branch}"
    control_access :get_snapshot,
                   resource: repo,
                   repo: repo,
                   allow_integrations: true,
                   allow_user_via_granular_actor: true

    output = repo_dependencies_provider.get_dependencies_for_repository(
      repository_id: repo.id,
      sha: repo.ref_to_sha(ref),
      owner_id: repo.owner_id,
      )

    if output[:errors].blank? && output[:response].present?
      return deliver :dependencies_hash, output[:response], status: output[:status_code]
    else
      deliver_snapshot_error output
    end
  end

  private

  def dependency_snapshot_provider
    @dependency_snapshot_provider ||= DependencySnapshot::DependencySnapshotProvider.new
  end

  def repo_dependencies_provider
    @repo_dependencies_provider ||= DependencyGraph::RepositoryDependenciesProvider.new
  end

  def deliver_snapshot_error(output)
    if output[:status_code].blank?
      GitHub.logger.with_named_tags({
        "gh.catalog_service": "github/dependency_graph"
      }) do
        GitHub.logger.warning("DependencySnapshotProvider did not return a status code")
      end
    end

    status_code = output.fetch(:status_code, 500)
    # Make sure we don't leak details from 5xx responses
    if status_code >= 500
      return deliver_error status_code, message: "An error occurred while processing your request. Please try again later."
    end
    # We want ds-api validation errors to match the openapi ones, so this is a special case
    if status_code >= 400 && output[:errors].present? && output[:errors].length >= 1
      errors = output[:errors].join("\n")
      deliver_error! status_code, message: errors
    end
    deliver_error status_code, errors: output[:errors]
  end
end
