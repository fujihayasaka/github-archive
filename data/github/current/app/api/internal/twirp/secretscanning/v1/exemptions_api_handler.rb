# typed: strict
# frozen_string_literal: true

require "secret_scanning_proto"

class Api::Internal::Twirp
  module Secretscanning
    module V1
      class ExemptionsAPIHandler < SecretScanningAPIHandler
        handles_service(GitHub::Proto::SecretScanning::Api::V1::ExemptionsAPIService)

        allow_access_for :client

        exempt_from_tenant_context_requirement(only: %i[get_exemption get_exemptions])

        EXEMPTION_RESPONSE_STATUS_TO_PROTO = T.let({
          "approved" => :APPROVED,
          "rejected" => :REJECTED,
        }, T::Hash[String, Symbol])

        EXEMPTION_TYPE_TO_PROTO = T.let({
          SecretScanning::ExemptionConstants::CLOSURE_EXEMPTION_REQUEST_TYPE => GitHub::Proto::SecretScanning::Api::V1::ExemptionType::CLOSURE_REQUEST,
          SecretScanning::ExemptionConstants::EXEMPTION_REQUEST_TYPE => GitHub::Proto::SecretScanning::Api::V1::ExemptionType::DELEGATED_BYPASS,
        }, T::Hash[String, Symbol])

        EXEMPTION_STATUS_TO_PROTO = T.let({
          "pending" => :PENDING,
          "approved" => :APPROVED,
          "rejected" => :REJECTED,
          "cancelled" => :CANCELLED,
        }, T::Hash[Symbol, Symbol])

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

          construct_get_exemption_response(exemption_request)
        end

        sig do
          params(
            req: GitHub::Proto::SecretScanning::Api::V1::GetExemptionsRequest,
            env: T::Hash[String, T.untyped]
          ).returns(
            T.any(
              GitHub::Proto::SecretScanning::Api::V1::GetExemptionsResponse,
              Twirp::Error
            )
          )
        end
        def get_exemptions(req, env)
          repo = Repository.find_by(id: req.repository_id)
          return Twirp::Error.not_found("failed to fetch repository", argument: "repository_id") unless repo

          requests = Exemptions::ExemptionRequest.where(
            # for now we only support closure exemption requests, but we may extend this in the future
            request_type: SecretScanning::ExemptionConstants::CLOSURE_EXEMPTION_REQUEST_TYPE,
            resource_owner_type: repo.class.name,
            resource_owner_id: repo.id,
            resource_identifier: req.resource_id,
          )
          .order(created_at: :asc)
          .includes(:latest_response)

          exemptions = requests.map do |request|
            construct_get_exemption_response(request)
          end

          GitHub::Proto::SecretScanning::Api::V1::GetExemptionsResponse.new(exemptions: exemptions)
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

        private

        sig { params(request: Exemptions::ExemptionRequest).returns(GitHub::Proto::SecretScanning::Api::V1::GetExemptionResponse) }
        def construct_get_exemption_response(request)
          response = unless request.latest_response.nil?
            latest_response = T.must(request.latest_response)
            GitHub::Proto::SecretScanning::Api::V1::ExemptionResponse.new(
              reviewer_id: latest_response.reviewer_id,
              created_at: Google::Protobuf::Timestamp.new(seconds: latest_response.created_at.to_i),
              status: EXEMPTION_RESPONSE_STATUS_TO_PROTO[latest_response.status],
              message: latest_response.message,
            )
          end

          GitHub::Proto::SecretScanning::Api::V1::GetExemptionResponse.new(
            exemption_request: GitHub::Proto::SecretScanning::Api::V1::ExemptionRequest.new(
              exemption_request_id: request.id,
              created_at: Google::Protobuf::Timestamp.new(seconds: request.created_at.to_i),
              updated_at: Google::Protobuf::Timestamp.new(seconds: request.updated_at.to_i),
              requester_id: request.requester_id,
              requester_comment: request.requester_comment,
              reason: self.class.to_proto_reason(request.metadata["reason"]),
              type: EXEMPTION_TYPE_TO_PROTO[request.request_type],
              status: EXEMPTION_STATUS_TO_PROTO[request.status],
            ),
            exemption_response: response,
          )
        end
      end
    end
  end
end
