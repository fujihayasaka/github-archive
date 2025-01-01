
# typed: true
# frozen_string_literal: true

require "secret_scanning_proto"

class Api::Internal::Twirp
  module Secretscanning
    module V1
      class BlobsAPIHandler < SecretScanningAPIHandler
        handles_service(GitHub::Proto::SecretScanning::Blobs::V1::BlobsAPIService)

        allow_access_for :client

        TOKEN_SCANNING_RPC_TIMEOUT = T.let(8.seconds, Integer)
        BLOB_OID_LIMIT = 1000

        resolve_tenant_context do |req, _env|
          ::Repositories::Public.resolve_tenant(id: req.repository_id)
        rescue ActiveRecord::RecordNotFound => err
          Twirp::Error.not_found(err.message)
        end

        # Public: Implementation of the GetLocations Twirp RPC.
        #
        # req - The Twirp request as a GitHub::Proto::SecretScanning::Blobs::V1::GetLocationsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response data, loading path information (commit +
        # path) for each provided blob. Returned value is a
        # GitHub::Proto::SecretScanning::Blobs::V1::GetLocationsResponse.
        sig do
          params(
            req: GitHub::Proto::SecretScanning::Blobs::V1::GetLocationsRequest,
            env: T::Hash[String, T.untyped]
          ).returns(
            T.any(
              GitHub::Proto::SecretScanning::Blobs::V1::GetLocationsResponse,
              Twirp::Error
            )
          )
        end
        def get_locations(req, env)
          repo = Repository.find_by(id: req.repository_id)
          unless repo.present?
            return Twirp::Error.invalid_argument("failed to fetch repository", argument: "repository_id")
          end

          blob_oids = req.blob_oids.to_a

          if blob_oids.size > BLOB_OID_LIMIT
            return Twirp::Error.invalid_argument("must have a length <= #{BLOB_OID_LIMIT}", argument: "blob_oids")
          end

          results = []
          begin
            lines = repo.rpc.with_timeout(TOKEN_SCANNING_RPC_TIMEOUT) do
              repo.rpc.list_revision_history_multiple([], findobjs: blob_oids)
            end
            lines.each do |line|
              blob, loc = line.split(" ", 2)
              commit_sha, path = loc.split("/", 2)

              results << {
                blob_oid: blob,
                commit_oid: commit_sha,
                path: path,
              }
            end
          rescue GitRPC::InvalidRepository
            # Repository has been deleted so report as no_repo result
            return Twirp::Error.not_found("Repository has been deleted", repo_id: repo.id.to_s)
          rescue GitRPC::Timeout
            return Twirp::Error.deadline_exceeded("Request took too long", repo_id: repo.id.to_s)
          rescue GitRPC::Error, GitHub::DGit::Error => e
            Failbot.report(e, repo_id: repo.id, blobs: blob_oids)
            return Twirp::Error.internal("gitrpc failure", repo_id: repo.id.to_s)
          end

          GitHub::Proto::SecretScanning::Blobs::V1::GetLocationsResponse.new({ attributed_blobs: results })
        end
      end
    end
  end
end
