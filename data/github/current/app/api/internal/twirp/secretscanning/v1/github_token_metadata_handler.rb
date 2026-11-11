# typed: strict
# frozen_string_literal: true

require "secret_scanning_proto"

class Api::Internal::Twirp
  module Secretscanning
    module V1
      # Handles requests from the token-scanning-service (TSS) for metadata about
      # GitHub-issued tokens (e.g. PATs, OAuth tokens, app tokens, deploy keys, PATv2)
      # that have been observed by secret scanning. TSS uses this to enrich and store
      # metadata for leaked GitHub credentials it captures in its own background jobs.
      class GitHubTokenMetadataHandler < SecretScanningAPIHandler
        handles_service(GitHub::Proto::SecretScanning::Api::V1::GithubTokenMetadataAPIService)

        allow_access_for :client

        resolve_tenant_context do |req, _env|
          ::Repositories::Public.resolve_tenant(id: req.repository_id)
        rescue ActiveRecord::RecordNotFound => err
          Twirp::Error.not_found(err.message)
        end

        # Public: Decrypts the supplied token and returns metadata about the
        # underlying GitHub credential (creation/expiry/last-accessed timestamps,
        # access id, owner id, name).
        #
        # req - GitHub::Proto::SecretScanning::Api::V1::GetGithubTokenMetadataRequest
        # _env - Twirp environment Hash.
        sig do
          params(
            req: GitHub::Proto::SecretScanning::Api::V1::GetGithubTokenMetadataRequest,
            _env: T::Hash[String, T.untyped],
          ).returns(T.any(GitHub::Proto::SecretScanning::Api::V1::GetGithubTokenMetadataResponse, Twirp::Error))
        end
        def get_github_token_metadata(req, _env)
          if req.token_type.blank?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "token_type")
          end

          if req.repository_id.nil?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "repository_id")
          end

          if req.repository_id == 0
            return Twirp::Error.invalid_argument("must be non-zero", argument: "repository_id")
          end

          if req.encrypted_token.blank?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "encrypted_token")
          end

          GitHub.dogstats.increment(
            "secretscanning_github_token_metadata.get.calls",
            tags: ["token_type:#{req.token_type}"],
          )

          raw_secret = SecretScanning::Encryption::EncryptedSecretsHelper.decrypt_raw_secret(
            req.encrypted_token,
            source: self.class.name,
          )
          if raw_secret.nil?
            return GitHub::Proto::SecretScanning::Api::V1::GetGithubTokenMetadataResponse.new
          end

          metadata = SecretScanning::Services::GitHubTokenMetadataService.new.get_github_token_metadata_by_raw_secret(
            raw_secret: raw_secret,
            token_type: req.token_type,
            repository_id: req.repository_id,
            number: req.number,
            is_base64_encoded: req.is_base64_encoded,
          )

          if metadata.nil?
            return GitHub::Proto::SecretScanning::Api::V1::GetGithubTokenMetadataResponse.new
          end

          # The per-token-type metadata helpers always return `org_access: nil`;
          # resolve it as a separate call (mirroring the existing dotcom controller
          # pattern) so the response carries org-access information when available.
          access_id = metadata.access_id
          org_access = if access_id
            SecretScanning::Services::GitHubTokenMetadataService.new.resolve_org_access_by_raw_secret(
              raw_secret: raw_secret,
              token_type: req.token_type,
              access_id: access_id,
              repository_id: req.repository_id,
              is_base64_encoded: req.is_base64_encoded,
            )
          end

          GitHub::Proto::SecretScanning::Api::V1::GetGithubTokenMetadataResponse.new(
            metadata: build_metadata_proto(metadata, org_access: org_access),
          )
        end

        private

        sig do
          params(
            metadata: SecretScanning::Models::GitHubTokenMetadata,
            org_access: T.nilable(Symbol),
          ).returns(GitHub::Proto::SecretScanning::Api::V1::GithubTokenMetadata)
        end
        def build_metadata_proto(metadata, org_access:)
          GitHub::Proto::SecretScanning::Api::V1::GithubTokenMetadata.new(
            created_at: metadata.created_at&.to_proto,
            expires_at: metadata.expires_at&.to_proto,
            last_accessed_at: metadata.last_accessed_at&.to_proto,
            org_access: map_org_access(org_access),
            access_id: metadata.access_id || 0,
            owner_id: metadata.owner_id || 0,
            name: metadata.name || "",
          )
        end

        # Maps the service's org-access Symbol (or nil) onto the proto enum.
        sig do
          params(org_access: T.nilable(Symbol))
            .returns(Symbol)
        end
        def map_org_access(org_access)
          case org_access
          when :NO_ACCESS
            :ORG_ACCESS_NO_ACCESS
          when :ORG_ACCESS
            :ORG_ACCESS_ORG_ACCESS
          when :SSO_ACCESS
            :ORG_ACCESS_SSO_ACCESS
          when :PUBLIC_ACCESS
            :ORG_ACCESS_PUBLIC_ACCESS
          else
            :ORG_ACCESS_INVALID
          end
        end
      end
    end
  end
end
