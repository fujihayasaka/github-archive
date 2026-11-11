# typed: strict
# frozen_string_literal: true

require "monolith-twirp-actions-core"

module Api::Internal::Twirp::Actions
  module Core
    module V1
      # Handler for the MonolithTwirp::Actions::Core::V1::TenantAPIService
      class TenantAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["launch"]
        handles_service MonolithTwirp::Actions::Core::V1::TenantAPIService

        sig { params(rack_env: T::Hash[Symbol, T.untyped], env: T::Hash[Symbol, T.untyped]).void }
        def before_rpc(rack_env, env)
          Twirp::Error.unavailable("Tenant info APIs not available outside of Proxima") unless GitHub.multi_tenant_enterprise?
        end

        # Public: Implementation of the GetTenantShortcode Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Actions::Core::V1::GetTenantShortcodeRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Actions::Core::V1::GetTenantShortcodeResponse, or a Twirp::Error.
        sig { params(req: MonolithTwirp::Actions::Core::V1::GetTenantShortcodeRequest, env: T::Hash[Symbol, T.untyped]).returns(T.any(T::Hash[Symbol, String], Twirp::Error)) }
        def get_tenant_shortcode(req, env)
          unless GitHub::Config::Proxima.current_stamp.present?
            return Twirp::Error.invalid_argument("cannot get shortcode for tenants on dotcom")
          end

          unless req.tenant_id.present? && req.tenant_id.nonzero?
            return Twirp::Error.invalid_argument("tenant_id is required")
          end

          tenant = Business.find_by(id: req.tenant_id)
          if tenant.nil?
            return Twirp::Error.not_found("Tenant not found")
          end

          {
            tenant_shortcode: tenant.shortcode
          }
        end
      end
    end
  end
end
