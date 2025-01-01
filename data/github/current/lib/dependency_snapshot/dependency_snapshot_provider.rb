# typed: true
# frozen_string_literal: true

require "dependency_graph/base_twirp_client_handler"

module DependencySnapshot
  class DependencySnapshotProvider
    def create_dependency_snapshot(repository:, req_body:)
      client_handler do
        response = client.create_dependency_snapshot(
          repository_id: repository.id,
          repository_nwo: repository.nwo,
          repository_owner_id: repository.owner_id,
          repository_public: repository.public,
          req_body: req_body,
        )

        raise DependencyGraph::BaseTwirpClient::Error.new "Invalid Create Dependency Snapshot response" if response.nil?

        {
          status_code: 201,
          response: response,
          errors: nil
        }
      end
    end

    def get_dependency_snapshot(repository:, snapshot_id:)
      client_handler do
        response = client.get_dependency_snapshot(
          repository_id: repository.id,
          snapshot_id: snapshot_id,
        )

        raise DependencyGraph::BaseTwirpClient::Error.new "Invalid Get Dependency Snapshot response" if response.nil?

        {
          status_code: 200,
          response: response,
          errors: nil
        }
      end
    end

    def get_dependency_snapshots_diff(repository:, query_params:)
      client_handler do
        response = client.get_dependency_snapshots_diff(
          repository_id: repository.id,
          base_snapshot_id: query_params[:base_snapshot_id],
          target_snapshot_id: query_params[:target_snapshot_id],
          base_ref: query_params[:base_ref],
          target_ref: query_params[:target_ref],
          base_sha: query_params[:base_sha],
          target_sha: query_params[:target_sha],
          base_build_type: query_params[:base_build_type],
          target_build_type: query_params[:target_build_type],
          base_build_id: query_params[:base_build_id],
          target_build_id: query_params[:target_build_id]
        )

        raise DependencyGraph::BaseTwirpClient::Error.new "Invalid Dependency Snapshot Diff response" if response.nil?

        {
          status_code: 200,
          response: response,
          errors: nil
        }
      end
    end

    def get_included_dependency_snapshots(repository:)
      client_handler do
        response = client.get_included_dependency_snapshots(repository_id: repository.id)

        raise DependencyGraph::BaseTwirpClient::Error.new "Invalid GetIncludedDependencySnapshots response" if response.nil?

        {
          status_code: 200,
          response: response,
          errors: nil
        }
      end
    end

    def exclude_dependency_snapshots(repository:, snapshot_ids:)
      client_handler do
        response = client.exclude_dependency_snapshots(repository_id: repository.id, snapshot_ids: snapshot_ids)

        raise DependencyGraph::BaseTwirpClient::Error.new "Invalid ExcludeDependencySnapshots response" if response.nil?

        {
          status_code: 200,
          response: response,
          errors: nil
        }
      end
    end

    private

    def client
      @client ||= DependencySnapshot::DependencySnapshotClient.new
    end

    def client_handler(&block)
      DependencyGraph::BaseTwirpClientHandler.client_handler({ class: "DependencyGraph::DependencySnapshotsProvider" }, true, block)
    end
  end
end
