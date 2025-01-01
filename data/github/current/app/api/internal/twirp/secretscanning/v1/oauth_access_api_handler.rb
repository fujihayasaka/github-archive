# typed: true
# frozen_string_literal: true

require "secret_scanning_proto"

class Api::Internal::Twirp
  module Secretscanning
    module V1
      class OauthAccessAPIHandler < SecretScanningAPIHandler
        handles_service(GitHub::Proto::SecretScanning::Api::V1::OauthAccessAPIService)

        allow_access_for :client
        connected_to_writing_for :revoke_oauth_access

        include GitHub::TokenScanning::TokenScanningPostProcessingHelper

        CANDIDATE_LIMIT = 1000

        resolve_tenant_context only: %i[revoke_oauth_access] do |req, _env|
          ::Repositories::Public.resolve_tenant(id: req.repository_id)
        rescue ActiveRecord::RecordNotFound => err
          Twirp::Error.not_found(err.message)
        end

        exempt_from_tenant_context_requirement(only: %i[verify_oauth_access])

        def revoke_oauth_access(req, env)
          candidates = req.candidates&.to_a

          unless candidates.present?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "candidates")
          end

          if candidates.size > CANDIDATE_LIMIT
            return Twirp::Error.invalid_argument("must have a length <= #{CANDIDATE_LIMIT}", argument: "candidates")
          end

          repo = with_read { get_repo_from_request(req.repository_type, req.repository_id) }

          tokens = candidates.map do |x|
            type = "GITHUB"
            if x.type.present?
              type = x.type
            end

            GitHub::TokenScanning::FoundToken.new(type: type, token: x.token, url: x.url, report_url: "", token_source: x.token_source)
          end

          is_one_click_revoke_request = req&.is_one_click_revoke_request || false

          tokens_with_updated_state = revoke_github_oauth_keys(tokens, repo, is_one_click_revoke_request, entry_point: :twirp_api_secretscanning_oauth_access_revoke_oauth_access)

          revoked_count = (tokens_with_updated_state.select { |token| token.state == :revoked }).count

          results = []

          candidates.each do |candidate|
            matches = tokens_with_updated_state.select { |token| token.type == candidate.type && token.token == candidate.token && token.url == candidate.url }
            if matches.nil? || matches.empty?
              results.push({ revoke_result: :NO_OAUTH_ACCESS })
            else
              case matches[0].state
              when :no_url
                results.push({ revoke_result: :NO_URL })
              when :no_oauth_access
                results.push({ revoke_result: :NO_OAUTH_ACCESS })
              when :revoked
                results.push({ revoke_result: :REVOKED })
              end
            end
          end

          { revoked_count: revoked_count, results: results }
        end

        def verify_oauth_access(req, env)
          candidates = req.candidates&.to_a

          unless candidates.present?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "candidates")
          end

          if candidates.size > CANDIDATE_LIMIT
            return Twirp::Error.invalid_argument("must have a length <= #{CANDIDATE_LIMIT}", argument: "candidates")
          end

          tokens = candidates.map do |x|
            type = "GITHUB"
            if x.type.present?
              type = x.type
            end

            GitHub::TokenScanning::FoundToken.new(type: type, token: x.token, url: "", report_url: "")
          end

          accesses = get_github_accesses(tokens)

          results = candidates.map do |candidate|
            verification_status = nil

            matches = tokens.select { |token| token.type == candidate.type && token.token == candidate.token }

            if matches.nil? || matches.empty?
              verification_status = :UNKNOWN
            else
              accesses_for_type = accesses[select_github_token_access_type(matches[0].type)]
              token_state = get_token_state_from_access(accesses_for_type, matches[0].type, matches[0].token)

              case token_state
              when :unknown
                verification_status = :UNKNOWN
              when :active
                verification_status = :ACTIVE
              when :revoked
                verification_status = :REVOKED
              when :unverifiable
                verification_status = :UNVERIFIABLE
              end
            end
            { is_verified: verification_status != :UNKNOWN, verification_status: verification_status }
          end

          { results: results }
        end
      end
    end
  end
end
