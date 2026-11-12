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
      # limit_to_files: optional DependencyGraphAPI::V1::LimitToFiles proto, which
      #                 will be translated to DS-API's ChangedFiles field on the request.
      # target_repository_id: GitHub repository ID for the target (head) side of the diff.
      #                       Defaults to 0, which tells DS-API to use repository_id for both sides.
      def get_snapshot_diff(repository_id, base_sha, target_sha, limit_to_files: nil, target_repository_id: 0)
        request = Github::DependencySnapshotsApi::GetSnapshotDiffRequest.new(
          repository_id: repository_id,
          basehead: "#{base_sha}...#{target_sha}",
          changed_files: build_changed_files(limit_to_files),
          target_repository_id: target_repository_id,
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

      private

      # Translates DG-API's LimitToFiles proto into DS-API's ChangedFiles proto.
      # Field mapping: target → head, blob_id → blob_oid.
      def build_changed_files(limit_to_files)
        return nil if limit_to_files.nil? || (limit_to_files.base.empty? && limit_to_files.target.empty?)

        Github::DependencySnapshotsApi::ChangedFiles.new(
          base: limit_to_files.base.map { |f| Github::DependencySnapshotsApi::ChangedFile.new(path: f.path, blob_oid: f.blob_id) },
          head: limit_to_files.target.map { |f| Github::DependencySnapshotsApi::ChangedFile.new(path: f.path, blob_oid: f.blob_id) },
        )
      end
    end
  end
end
