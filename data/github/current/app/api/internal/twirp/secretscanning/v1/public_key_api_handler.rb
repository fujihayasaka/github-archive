# typed: true
# frozen_string_literal: true

require "secret_scanning_proto"

class Api::Internal::Twirp
  module Secretscanning
    module V1
      class PublicKeyAPIHandler < SecretScanningAPIHandler
        handles_service(GitHub::Proto::SecretScanning::Api::V1::PublicKeyAPIService)

        allow_access_for :client
        connected_to_writing_for :unverify_public_key

        include GitHub::TokenScanning::TokenScanningPostProcessingHelper

        CANDIDATE_LIMIT = 250

        resolve_tenant_context do |req, _env|
          ::Repositories::Public.resolve_tenant(id: req.repository_id)
        rescue ActiveRecord::RecordNotFound => err
          Twirp::Error.not_found(err.message)
        end

        sig { params(req: GitHub::Proto::SecretScanning::Api::V1::UnverifyPublicKeyRequest, env: T.untyped).returns(T.any(GitHub::Proto::SecretScanning::Api::V1::UnverifyPublicKeyResponse, Twirp::Error)) }
        def unverify_public_key(req, env)
          candidates = req.candidates.to_a

          return Twirp::Error.invalid_argument("must be non-empty", argument: "candidates")  unless candidates.present?
          return Twirp::Error.invalid_argument("must have a length <= #{CANDIDATE_LIMIT}", argument: "candidates") if candidates.size > CANDIDATE_LIMIT
          return Twirp::Error.invalid_argument("must be a valid repository ID", argument: "repository_id") unless req.repository_id > 0
          return Twirp::Error.invalid_argument("must be a valid repository type", argument: "repository_type") if req.repository_type == :UNKNOWN_TYPE

          repo = with_read { get_repo_from_request(req.repository_type, req.repository_id) }

          if repo.nil?
            return Twirp::Error.invalid_argument("failed to fetch repository or gist", argument: "repository_id")
          end

          tokens = candidates.map { |x| GitHub::TokenScanning::FoundToken.new(type: x.type, token: x.private_key, url: x.url, report_url: "", token_source: x.token_source) }

          unverified = revoke_github_ssh_private_keys(tokens, repo)

          unverified_count = (unverified.select { |token| token.state == :unverified }).count

          results = []

          candidates.map do |candidate|
            matches = unverified.select { |token| token.type == candidate.type && token.token == candidate.private_key && token.url == candidate.url }
            if matches.empty?
              results.push({ unverify_result: :NO_PUBLIC_KEY })
            else
              case matches[0]&.state
              when :no_url
                results.push({ unverify_result: :NO_URL })
              when :no_public_key
                results.push({ unverify_result: :NO_PUBLIC_KEY })
              when :unverified
                results.push({ unverify_result: :UNVERIFIED })
              when :already_unverified
                results.push({ unverify_result: :ALREADY_UNVERIFIED })
              end
            end
          end

          GitHub::Proto::SecretScanning::Api::V1::UnverifyPublicKeyResponse.new(unverified_count: unverified_count, results: results)
        end

        sig { params(req: GitHub::Proto::SecretScanning::Api::V1::VerifyPrivateKeyRequest, env: T.untyped).returns(T.any(GitHub::Proto::SecretScanning::Api::V1::VerifyPrivateKeyResponse, Twirp::Error)) }
        def verify_private_key(req, env)
          repo = nil
          candidates = req.candidates.to_a

          unless candidates.present?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "candidates")
          end

          if candidates.size > CANDIDATE_LIMIT
            return Twirp::Error.invalid_argument("must have a length <= #{CANDIDATE_LIMIT}", argument: "candidates")
          end

          if GitHub.multi_tenant_enterprise?
            # must provide a valid repository context on multi-tenant
            return Twirp::Error.invalid_argument("must be a valid repository ID", argument: "repository_id") unless req.repository_id > 0
            return Twirp::Error.invalid_argument("must be a valid repository type", argument: "repository_type") if req.repository_type == :UNKNOWN_TYPE

            repo = with_read { get_repo_from_request(req.repository_type, req.repository_id) }

            return Twirp::Error.invalid_argument("could not find repository or gist", argument: "repository_id") if repo.nil?
          end

          private_keys = candidates.map(&:private_key)
          fingerprints = ssh_key_fingerprints(private_keys, repo)
          public_keys = public_keys_for_fingerprints(fingerprints.values.compact)

          results = candidates.map do |candidate|
            fingerprint = fingerprints[candidate.private_key]
            key = public_keys[T.must(fingerprint)]
            verification_status = nil
            if key.nil?
              verification_status = :UNKNOWN
            elsif key.verified?
              verification_status = :ACTIVE
            else
              verification_status = :REVOKED
            end
            GitHub::Proto::SecretScanning::Api::V1::VerifyPrivateKeyResponse::PrivateKey.new(is_verified: key.present?, verification_status: verification_status)
          end

          GitHub::Proto::SecretScanning::Api::V1::VerifyPrivateKeyResponse.new(results: results)
        end
      end
    end
  end
end
