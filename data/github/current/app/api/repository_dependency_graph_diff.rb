# typed: true
# frozen_string_literal: true

class Api::RepositoryDependencyGraphDiff < Api::App
  include DependencyReviewHelper
  include ReceiveSchemaWithOpenApi

  # DR-specific access checks are performed here
  before do
    enforce_dependency_review_access
  end

  # timing measured automatically via "request.dist.time" and filtering on controller name
  get "/repositories/:repository_id/dependency-graph/compare/:basehead", operation_id: "dependency-graph/diff-range" do
    control_access :get_contents,
      resource: current_repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    # extract and resolve base and head params
    base, head = params[:basehead].split("...", 2)
    unless base && head
      GitHub.dogstats.increment("dependency_graph.dependency_review.api.diff_range.error", tags: ["diff_range:missing"])
      deliver_error!(400)
    end

    # NOTE: the outward-facing parameter is includes_dependency_snapshots (with an "s")
    # to fit with REST API conventions. However, in every other case we use
    # include_dependency_snapshots (without an "s") because that's what the
    # DG-API backend expects.
    include_dependency_snapshots = params[:includes_dependency_snapshots] == "true"

    # Resolve valid Git revisions into merge base and HEAD commit SHAs
    # representing a diff range we can pass to the DG-API backend
    start_comparison_time = GitHub::Dogstats.monotonic_time
    base_sha, head_sha = resolve_diff_range(current_repo, base, head)
    elapsed = GitHub::Dogstats.duration(start_comparison_time)
    GitHub.dogstats.distribution("dependency_graph.dependency_review.api.diff_range.resolve", elapsed)

    unless base_sha && head_sha
      GitHub.dogstats.increment("dependency_graph.dependency_review.api.diff_range.error", tags: ["diff_range:invalid"])
      deliver_error!(400)
    end

    page, per_page = resolve_api_pagination_params(params)

    diff = get_shas_diff(repo: current_repo, base_sha: base_sha, target_sha: head_sha,
                         decompose_updates: true, load_vulns: true,
                         include_dependency_snapshots: include_dependency_snapshots,
                         page: page, per_page: per_page)

    @meta["X-GitHub-Dependency-Graph-Snapshot-Warnings"] = format_snapshot_warnings(diff&.snapshot_warnings)

    if diff&.page_metadata
      @paginator = build_paginator(default_per_page: diff.page_metadata.per_page, max_per_page: diff.page_metadata.per_page)
      # paginator needs to know approx number of items in full diff to
      # generate Link headers with expected paging metadata for the response
      @paginator.collection_size = diff.page_metadata.per_page * diff.page_metadata.last
    end

    api_response_diff = reshape_for_api_response(diff)
    deliver_raw(api_response_diff)
  end

  # Ensure current repo and user are cached and coarse-grained
  # access checks are performed before controller actions
  def enforce_dependency_review_access
    deliver_error!(404) if !logged_in?
    deliver_error!(404) unless current_repo
    deliver_error!(403, message: "Forbidden") unless current_repo.dependency_review_enabled?
  end

  # If warnings is non-empty, join them into a single string and
  # base64-encode the result for safe transport in the response headers.
  def format_snapshot_warnings(warnings)
    return nil if warnings.nil? || warnings.empty?

    Base64.strict_encode64(warnings.join("\n"))
  end
end
