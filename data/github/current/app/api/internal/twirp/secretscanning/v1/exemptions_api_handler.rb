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

          # Take the most recent ExemptionResponse. Only include it if it's been approved.
          most_recent_exemption_response = exemption_request.responses[-1]
          unless most_recent_exemption_response&.status == "approved"
            return Twirp::Error.not_found("no approved response for exemption request", argument: "exemption_request_id")
          end

          GitHub::Proto::SecretScanning::Api::V1::GetExemptionResponse.new({
            exemption_request:  GitHub::Proto::SecretScanning::Api::V1::ExemptionRequest.new(
              exemption_request_id: exemption_request.id,
              created_at: Google::Protobuf::Timestamp.new(seconds: exemption_request.created_at.to_i),
              requester_id: exemption_request.requester_id,
              requester_comment: exemption_request.requester_comment,
            ),
            exemption_response: GitHub::Proto::SecretScanning::Api::V1::ExemptionResponse.new(
              reviewer_id: most_recent_exemption_response.reviewer_id,
              created_at: Google::Protobuf::Timestamp.new(seconds: most_recent_exemption_response.created_at.to_i),
              status: :APPROVED,
            )
            })
        end
      end
    end
  end
end
