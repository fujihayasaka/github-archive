# typed: true
# frozen_string_literal: true

require "dependency_graph/base_twirp_client"

module DependencyReview
  class SnapshotClient < DependencyGraph::BaseTwirpClient
    # target_repository_id (optional) - When the head SHA lives on a fork in
    # current_repo's network (typical for fork-PR Dependency Review Action calls),
    # the discovered fork repo id is forwarded to DG-API so it can resolve the
    # head-side snapshot against the fork's data instead of the upstream's.
    def get_snapshots_diff(repository_id:, base_sha:, target_sha:, repository_nwo:, repository_public:, repository_owner_id:, limit_to_files:, decompose_updates: false, page: nil, per_page: nil, target_repository_id: nil, org_id: nil, business_id: nil)
      rpc_request = {
        repository_id: repository_id,
        base_sha: base_sha,
        target_sha: target_sha,
        limit_to_files: limit_to_files,
        decompose_updates: decompose_updates,
      }

      rpc_request[:org_id] = org_id if org_id
      rpc_request[:business_id] = business_id if business_id

      if target_repository_id && target_repository_id != repository_id
        rpc_request[:target_repository_id] = target_repository_id
      end

      if page || per_page
        # nil per_page on dg-api will default to our default max (1000)
        rpc_request[:page_metadata] = { page: page, per_page: per_page }
      end

      GitHub.dogstats.count("dependency_graph.dependency_review.files_count", limit_to_files.count)
      GitHub.dogstats.time("dependency_graph.dependency_review.get_snapshots_diff.time") do
        rpc(:GetSnapshotsDiff, rpc_request)
      end
    end

    private

    def twirp_class
      DependencyGraphAPI::V1::SnapshotAPIClient
    end

    def twirp_url_namespace
      "snapshots"
    end
  end
end
