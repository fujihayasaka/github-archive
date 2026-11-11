# typed: strict
# frozen_string_literal: true

require "secret_scanning_proto"

class Api::Internal::Twirp
  module Secretscanning
    module V1
      class BusinessApiHandler < SecretScanningAPIHandler
        handles_service(GitHub::Proto::SecretScanning::Businesses::V1::BusinessAPIService)

        allow_access_for :client

        exempt_from_tenant_context_requirement

        sig do
          params(
            req: GitHub::Proto::SecretScanning::Businesses::V1::GetBusinessRequest,
            env: T::Hash[String, T.untyped]
          ).returns(
            T.any(
              GitHub::Proto::SecretScanning::Businesses::V1::GetBusinessResponse,
              Twirp::Error
            )
          )
        end
        def get_business(req, env)
          unless req.biz_id.present? && req.biz_id > 0
            return Twirp::Error.invalid_argument("must be a positive integer", argument: "biz_id")
          end

          business = Business.find_by(id: req.biz_id)

          unless business.present?
            return Twirp::Error.not_found("failed to find business", argument: "biz_id")
          end

          result = GitHub::Proto::SecretScanning::Businesses::V1::Business.new(
            id: business.id,
            name: business.name,
            slug: business.slug
          )

          GitHub::Proto::SecretScanning::Businesses::V1::GetBusinessResponse.new(business: result)
        end
      end
    end
  end
end
