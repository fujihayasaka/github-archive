# typed: true
# frozen_string_literal: true

require "dependency_graph/base_twirp_client"

module DependencySnapshot
  class DependencySnapshotClient < DependencyGraph::BaseTwirpClient
    def initialize
      super(retryable: false)
    end

    def create_dependency_snapshot(repository_id:, repository_nwo:, repository_public:, repository_owner_id:, req_body:)
      # serialize Repository model meta captured at snapshot submit time
      repository_metadata = {
        nwo: repository_nwo,
        public: repository_public,
        owner_id: repository_owner_id
      }

      # wrap it all in the Twirp request payload
      rpc_request = {
        repository_id: repository_id,
        repository_metadata: repository_metadata,
        payload: req_body.to_json
      }

      rpc(:CreateDependencySnapshot, rpc_request)
    end

    def get_dependency_snapshot(repository_id:, snapshot_id:)
      rpc_request = {
        repository_id: repository_id,
        snapshot_id: snapshot_id,
      }

      rpc(:GetDependencySnapshot, rpc_request)
    end

    def get_dependency_snapshots_diff(
      repository_id:,
      base_snapshot_id:,
      target_snapshot_id:,
      base_ref: nil,
      target_ref: nil,
      base_sha: nil,
      target_sha: nil,
      base_build_type: nil,
      target_build_type: nil,
      base_build_id: nil,
      target_build_id: nil
    )

      rpc_request = {
        base_repository_id: repository_id,
        target_repository_id: repository_id,
        base_snapshot_id: base_snapshot_id,
        target_snapshot_id: target_snapshot_id,
        base_ref: base_ref,
        target_ref: target_ref,
        base_sha: base_sha,
        target_sha: target_sha,
        base_build_type: base_build_type,
        target_build_type: target_build_type,
        base_build_id: base_build_id,
        target_build_id: target_build_id
      }

      rpc(:GetDependencySnapshotsDiff, rpc_request)
    end

    def get_included_dependency_snapshots(repository_id:)
      rpc_request = {
        repository_id: repository_id
      }

      rpc(:GetIncludedDependencySnapshots, rpc_request)
    end

    def exclude_dependency_snapshots(repository_id:, snapshot_ids:)
      rpc_request = {
        repository_id: repository_id,
        snapshot_ids: snapshot_ids
      }

      rpc(:ExcludeDependencySnapshots, rpc_request)
    end

    private

    def twirp_class
      DependencyGraphAPI::V1::DependencySnapshotAPIClient
    end

    def twirp_url_namespace
      "dependency-snapshots"
    end
  end
end
