# typed: true
# frozen_string_literal: true

require "monolith-twirp-loops-core"

module Api::Internal::Twirp::Loops
  module Core
    module V1
      # Handler for the MonolithTwirp::Loops::Core::V1::AuthorizationAPIService
      class AuthorizationAPIHandler < Api::Internal::Twirp::Handler
        include FeatureFlagHelper

        MAX_BATCH_CONTROL_ACCESS_SIZE = 50

        allow_access_for :client, allowed_clients: ["loops"]
        handles_service MonolithTwirp::Loops::Core::V1::AuthorizationAPIService


        # Public: Implementation of the BatchControlAccess Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Loops::Core::V1::BatchControlAccessRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response either as a
        # MonolithTwirp::Loops::Core::V1::BatchControlAccessResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Loops::Core::V1::BatchControlAccessRequest,
            env: T::Hash[String, T.untyped]
          ).returns(T.any(MonolithTwirp::Loops::Core::V1::BatchControlAccessResponse, Twirp::Error))
        end
        def batch_control_access(req, env)
          return Twirp::Error.invalid_argument("token is required", argument: "access_token") if req.access_token.blank?

          begin
            decrypted_token = decrypt_token(T.must(req.access_token))
            token = decrypted_token.to_s
          rescue
            return Twirp::Error.invalid_argument("failed to decrypt token", argument: "access_token")
          end

          return Twirp::Error.invalid_argument("failed to decrypt token", argument: "access_token") if token.blank?

          resources = T.must(req.authorization_requests)

          return Twirp::Error.invalid_argument("too many resources", argument: "authorization_requests") if resources.size > MAX_BATCH_CONTROL_ACCESS_SIZE

          checker = Loops::AccessVerifiers::PlatformPermissionChecker.new(
            token: token,
            remote_ip: req.request_ip,
          )

          resources_map = resources.each_with_object({}) do |request, hash|
            hash[request.resource_id] = request.resource_type
          end
          result = checker.verify_batch(resources_map)

          response = result.results.map do |global_relay_id, accessible|
            MonolithTwirp::Loops::Core::V1::AuthorizationDecision.new(
              decision: accessible,
              resource_id: global_relay_id,
              resource_type: resources_map[global_relay_id],
            )
          end

          MonolithTwirp::Loops::Core::V1::BatchControlAccessResponse.new(decisions: response)
        rescue
          Twirp::Error.not_found("user not found or token invalid")
        end

        private

        def decrypt_token(token)
          GitHub.decode_and_decrypt_loops_token(token)
        end
      end
    end
  end
end
