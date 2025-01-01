require_relative "ds_api_client"

module DependencyGraphAPI
  module DependencySnapshotsAPI
    class SnapshotsClient
      include DSAPIClient
      # create_dependency_snapshot: proxies dotcom snapshot submissions to DS-API.
      #
      # repository_id: GitHub repository ID (unsigned nonzero integer)
      #
      # snapshot_payload: submitted snapshot JSON, as protobuf "bytes" field.
      #                   Twirp's Ruby binding encodes this as a string that
      #                   is base64 encoded/decoded by Twirp for the wire, and
      #                   accessible as a plain JSON string in the code.
      #                   DG-API will now proxy this string across to DS-API
      #                   without unmarshaling the JSON for processing.
      #
      def create_dependency_snapshot(repository_id, snapshot_payload)
        request = Github::DependencySnapshotsApi::CreateDependencySnapshotRequest.new(
          repository_id: repository_id,
          payload: snapshot_payload.to_s.b, # payload JSON string must be ASCII bytes for protobuf transport
        )

        write_client.create_dependency_snapshot(request)
      end

      # get_dependency_snapshot: retrieve a previously submitted snapshot by it's
      #                     GitHub repository ID and DS-API snapshot ID.
      #
      # repository_id: GitHub repository ID (unsigned nonzero integer)
      #
      # snapshot_id: DS-API PK for this build time snapshot (unsigned nonzero integer)
      #
      def get_dependency_snapshot(repository_id, snapshot_id)
        request = Github::DependencySnapshotsApi::GetDependencySnapshotRequest.new(
          repository_id: repository_id,
          snapshot_id: snapshot_id)

        client.get_dependency_snapshot(request)
      end

      # get_snapshot_diff: compare all relevant snapshots from the two given SHAs
      #                    and return a list of changes.
      #
      # repository_id: GitHub repository ID (unsigned nonzero integer)
      # base_sha:      base SHA to compare against (40-character hexadecimal string)
      # target_sha:    target SHA to compare (40-character hexadecimal string)
      def get_snapshot_diff(repository_id, base_sha, target_sha)
        request = Github::DependencySnapshotsApi::GetSnapshotDiffRequest.new(
          repository_id: repository_id,
          basehead: "#{base_sha}...#{target_sha}"
        )

        client.get_snapshot_diff(request)
      end

      # get_default_snapshot_for_repository: retrieve the "default" (usually, latest on
      #                                  default branch) snapshot by it's GitHub repository id.
      #
      # repository_id: GitHub repository ID (unsigned nonzero integer)
      #
      def get_default_snapshot_for_repository(repository_id)
        request = Github::DependencySnapshotsApi::GetDependencySnapshotRequest.new(
          repository_id: repository_id)

        client.get_dependency_snapshot(request)
      end

      def get_included_dependency_snapshots(repository_id)
        request = Github::DependencySnapshotsApi::GetIncludedDependencySnapshotsRequest.new(
          repository_id: repository_id
        )

        client.get_included_dependency_snapshots(request)
      end

      def exclude_dependency_snapshots(repository_id, snapshot_ids)
        request = Github::DependencySnapshotsApi::ExcludeDependencySnapshotsRequest.new(
          repository_id: repository_id,
          snapshot_ids: snapshot_ids
        )

        write_client.exclude_dependency_snapshots(request)
      end

      def client
        @client ||= Github::DependencySnapshotsApi::SnapshotsServiceClient.new(connection)
      end

      def write_client
        @write_client ||= Github::DependencySnapshotsApi::SnapshotsServiceClient.new(write_connection)
      end
    end
  end
end
