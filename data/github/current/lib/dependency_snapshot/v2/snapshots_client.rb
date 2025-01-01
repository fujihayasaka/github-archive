# typed: true
# frozen_string_literal: true

require "dependency-snapshots-api-proto"

module DependencySnapshot
  module V2
    class SnapshotsClient < DependencySnapshot::BaseClient
      extend T::Sig

      sig do
        params(sha: String, ref: String, scanned_at: Time, snapshot_payload: String, repository: ::Repository,
              received_at: Time, push: Repositories::IPush, pull_request: T.nilable(Object))
        .returns(Github::DependencySnapshotsApi::V2::AsyncCreateSnapshotResponse)
      end
      def async_create_snapshot(sha:, ref:, scanned_at:, snapshot_payload:, repository:,
                                received_at:, push:, pull_request: nil)

        repo_entity = DependencySnapshot::EntitySerializer::Repository.serialize(repository)
        owner_entity = DependencySnapshot::EntitySerializer::User.serialize(T.must(repository.owner)) if repository.owner
        push_entity = DependencySnapshot::EntitySerializer::Push.serialize(push)

        response = rpc("AsyncCreateSnapshot", {
          sha: sha,
          ref: ref,
          scanned_at: scanned_at,
          snapshot_payload: snapshot_payload,
          repository: repo_entity,
          repository_owner: owner_entity,
          received_at: received_at,
          push: push_entity,
          pull_request: pull_request,
        })

        # If the response is an error, it will raise an error. So if we get a response here,
        # it will be a response in the shape of the response object.
        T.cast(response, Github::DependencySnapshotsApi::V2::AsyncCreateSnapshotResponse)
      end

      def twirp_class
        Github::DependencySnapshotsApi::V2::SnapshotsClient
      end
    end
  end
end
