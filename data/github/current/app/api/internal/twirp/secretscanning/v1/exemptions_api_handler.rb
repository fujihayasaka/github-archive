# typed: strict
# frozen_string_literal: true

require "secret_scanning_proto"

class Api::Internal::Twirp
  module Secretscanning
    module V1
      class ExemptionsAPIHandler < SecretScanningAPIHandler
        handles_service(GitHub::Proto::SecretScanning::Api::V1::ExemptionsAPIService)

        allow_access_for :client

        exempt_from_tenant_context_requirement(only: %i[get_exemption])

        EXEMPTION_RESPONSE_STATUS_TO_PROTO = T.let({
          "approved" => :APPROVED,
          "rejected" => :REJECTED,
        }, T::Hash[String, Symbol])

        sig do
          params(
            req: GitHub::Proto::SecretScanning::Api::V1::GetExemptionRequest,
            env: T::Hash[String, T.untyped]
          ).returns(
            T.any(
              GitHub::Proto::SecretScanning::Api::V1::GetExemptionResponse,
              Twirp::Error
            )
          )
        end
        def get_exemption(req, env)
          exemption_request = Exemptions::ExemptionRequest.find_by(id: req.exemption_request_id)
          unless exemption_request.present?
            return Twirp::Error.not_found("failed to fetch exemption request", argument: "exemption_request_id")
          end

          # Take the most recent ExemptionResponse
          most_recent_exemption_response = exemption_request.responses[-1]
          response_to_return = nil
          if !most_recent_exemption_response.nil?
            response_to_return = GitHub::Proto::SecretScanning::Api::V1::ExemptionResponse.new(
              reviewer_id: most_recent_exemption_response.reviewer_id,
              created_at: Google::Protobuf::Timestamp.new(seconds: most_recent_exemption_response.created_at.to_i),
              status: EXEMPTION_RESPONSE_STATUS_TO_PROTO[most_recent_exemption_response.status],
              message: most_recent_exemption_response.message,
            )
          end

          GitHub::Proto::SecretScanning::Api::V1::GetExemptionResponse.new({
            exemption_request:  GitHub::Proto::SecretScanning::Api::V1::ExemptionRequest.new(
              exemption_request_id: exemption_request.id,
              created_at: Google::Protobuf::Timestamp.new(seconds: exemption_request.created_at.to_i),
              requester_id: exemption_request.requester_id,
              requester_comment: exemption_request.requester_comment,
              reason: self.class.to_proto_reason(exemption_request.metadata["reason"])
            ),
            exemption_response: response_to_return,
            })
        end

        sig { params(reason: T.nilable(String)).returns(T.nilable(Integer)) }
        def self.to_proto_reason(reason)
          case reason
          when nil
            nil
          when "false_positive"
            GitHub::Proto::SecretScanning::Api::V1::ExemptionReason::EXEMPTION_REASON_FALSE_POSITIVE
          when "used_in_tests"
            GitHub::Proto::SecretScanning::Api::V1::ExemptionReason::EXEMPTION_REASON_USED_IN_TESTS
          when "wont_fix"
            GitHub::Proto::SecretScanning::Api::V1::ExemptionReason::EXEMPTION_REASON_WONT_FIX
          when "revoked"
            GitHub::Proto::SecretScanning::Api::V1::ExemptionReason::EXEMPTION_REASON_REVOKED
          else
            GitHub::Proto::SecretScanning::Api::V1::ExemptionReason::EXEMPTION_REASON_UNKNOWN
          end
        end
      end
    end
  end
end
