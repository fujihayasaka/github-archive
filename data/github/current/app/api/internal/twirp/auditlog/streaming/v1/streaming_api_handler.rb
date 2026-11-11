# typed: true
# frozen_string_literal: true

require "monolith-twirp-auditlog-streaming"

module Api::Internal::Twirp::Auditlog
  module Streaming
    module V1
      # Handler for the MonolithTwirp::Auditlog::Streaming::V1::StreamingAPIService
      class StreamingAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["auditlog"]
        handles_service MonolithTwirp::Auditlog::Streaming::V1::StreamingAPIService
        exempt_from_tenant_context_requirement

        # Public: Implementation of the Configuration Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Auditlog::Streaming::V1::ConfigurationRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Auditlog::Streaming::V1::ConfigurationResponse, or a Twirp::Error.
        def configuration(req, env)
          AuditLogStreamConfiguration.streaming_api_confs
        end

        # Public: Implementation of the ConfigurationWithLimit Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Auditlog::Streaming::V1::ConfigurationWithLimitRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Auditlog::Streaming::V1::ConfigurationWithLimitResponse, or a Twirp::Error.
        def configuration_with_limit(req, env)
          streams = AuditLogStreamConfiguration.streaming_api_confs_with_offset(limit: req.limit, offset: req.offset)
          count = streams.map { |_, v| v.count }.sum
          streams.merge({ count: count, offset: req.offset })
        end

        # Public: Implementation of the ResolveExternalIdentity Twirp RPC.
        #
        # Resolves the actor's Entra object id for (user_id, business_id) from
        # the business's ExternalIdentity. Returns an empty string when no
        # identity with a non-empty external_id exists for the pair, or when
        # the identity's provider is not Azure AD / Entra ID (the only IdP
        # whose external_id is an Entra object id).
        #
        # req - The Twirp request as a MonolithTwirp::Auditlog::Streaming::V1::ResolveExternalIdentityRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns a Hash suitable for use in a
        # MonolithTwirp::Auditlog::Streaming::V1::ResolveExternalIdentityResponse, or a Twirp::Error.
        def resolve_external_identity(req, env)
          if req.user_id.zero? || req.business_id.zero?
            return Twirp::Error.invalid_argument("user_id and business_id are required")
          end

          identity = ExternalIdentity
            .for_user_in_business(user_id: req.user_id, business_id: req.business_id)
            .where.not(external_id: [nil, ""])
            .first

          external_id = if identity && identity.provider&.find_provider_type == :azure_ad
            identity.external_id
          end

          { actor_entra_object_id: external_id || "" }
        end
      end
    end
  end
end
