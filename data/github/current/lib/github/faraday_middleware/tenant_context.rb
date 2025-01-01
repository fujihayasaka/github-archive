# typed: true
# frozen_string_literal: true

module GitHub
  module FaradayMiddleware
    # Faraday middleware that inserts the headers required for tenant
    # context propagation to downstream services.
    class TenantContext < ::Faraday::Middleware
      TENANT_HEADER = "X-GitHub-Tenant".freeze
      TENANT_ID_HEADER = "X-GitHub-Tenant-ID".freeze

      def call(env)
        if current_tenant = GitHub::CurrentTenant.get.presence
          env.request_headers[TENANT_HEADER] = current_tenant.slug
          env.request_headers[TENANT_ID_HEADER] = current_tenant.id.to_s
        end

        @app.call(env)
      end

    end
  end
end
