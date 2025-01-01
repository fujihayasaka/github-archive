# typed: true
# frozen_string_literal: true

require "secret_scanning_proto"

class Api::Internal::Twirp
  module Secretscanning
    module V1
      class TenantAPIHandler < SecretScanningAPIHandler
        handles_service(GitHub::Proto::SecretScanning::Tenant::V1::TenantAPIService)

        allow_access_for :client

        # We don't have to resolve the tenant here, since we are already doing that in the RPC
        exempt_from_tenant_context_requirement

        sig do
          params(
            req: GitHub::Proto::SecretScanning::Tenant::V1::GetTenantRequest,
            env: T::Hash[String, T.untyped]
            )
          .returns(T.any(GitHub::Proto::SecretScanning::Tenant::V1::GetTenantResponse, Twirp::Error))
        end
        def get_tenant(req, env)
          unless req.repo_id.present?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "repo id")
          end

          tenant = ::Repositories::Public.resolve_tenant(id: req.repo_id)

          if tenant.nil?
            return Twirp::Error.not_found("tenant not found for repository id: #{req.repo_id}")
          end

          GitHub::Proto::SecretScanning::Tenant::V1::GetTenantResponse.new(
            tenant_slug: tenant.slug
          )
        end
      end
    end
  end
end
