# typed: true
# frozen_string_literal: true
require "dependency_graph/base_twirp_client"

module DependencyReview
  class SnapshotClient < DependencyGraph::BaseTwirpClient
    def get_snapshots_diff(repository_id:, base_sha:, target_sha:, repository_nwo:, repository_public:, repository_owner_id:, limit_to_files:, decompose_updates: false, include_dependency_snapshots: false, page: nil, per_page: nil)
      rpc_request = {
        repository_id: repository_id,
        base_sha: base_sha,
        target_sha: target_sha,
        limit_to_files: limit_to_files,
        decompose_updates: decompose_updates,
      }
      rpc_request[:include_dependency_snapshots] = true if include_dependency_snapshots || include_dependency_snapshots?(repository_id)

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

    def include_dependency_snapshots?(repository_id)
      begin
        repo = Repositories::Public.find_active!(repository_id)
        GitHub.flipper[:dependency_graph_dependency_review_include_dependency_snapshots].enabled?(repo) ||
          GitHub.flipper[:dependency_graph_dependency_review_include_dependency_snapshots].enabled?(repo.owner)
      rescue ActiveRecord::RecordNotFound
        # This sometimes happens in tests. It shouldn't ever happen in prod,
        # but if it does then we have bigger problems to worry about.
        false
      end
    end
  end
end
