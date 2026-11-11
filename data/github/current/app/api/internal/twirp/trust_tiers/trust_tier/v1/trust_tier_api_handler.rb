# typed: true
# frozen_string_literal: true

require "monolith-twirp-trusttiers-trusttier"

module Api::Internal::Twirp::TrustTiers
  module TrustTier
    module V1
      # Handler for the MonolithTwirp::TrustTiers::TrustTier::V1::TrustTierAPIService
      class TrustTierAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["launch"].freeze
        handles_service MonolithTwirp::TrustTiers::TrustTier::V1::TrustTierAPIService

        def before_rpc(rack_env, env)
          # grab client name here for logs/stats; not available later
          if (client_key = rack_env[:request_hmac_key])
            env[:client_name] = GitHub.api_internal_twirp_hmac_settings[client_key]
          end
        end

        # Public: Implementation of the GetTrustTier Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::TrustTiers::TrustTier::V1::GetTrustTierRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::TrustTiers::TrustTier::V1::GetTrustTierResponse, or a Twirp::Error.
        def get_trust_tier(req, env)
          GetTrustTier.call(req, env)
        end

        # Resolves the tenant for proxima
        resolve_tenant_context do |req, _env|
          actor_type, actor_id = Platform::Helpers::NodeIdentification.from_global_id(req.id.global_id)
          begin
            actor = case actor_type
            when "User"
              next User.find_by(id: actor_id)&.enterprise_managed_business
            when "Organization"
              next Organization.find_by(id: actor_id)&.resolve_tenant
            when "Repository"
              next Repositories::Public.resolve_tenant(id: actor_id)
            when "Enterprise"
              Business.find_by(id: actor_id)
            when "Bot"
              next Bot.find_by(id: actor_id)&.resolve_tenant
            end

            if actor.nil?
              return Twirp::Error.not_found("actor does not exist", argument: "id")
            end

          rescue ActiveRecord::RecordNotFound => err
            Twirp::Error.not_found(err.message)
          end
        end
      end
    end
  end
end
