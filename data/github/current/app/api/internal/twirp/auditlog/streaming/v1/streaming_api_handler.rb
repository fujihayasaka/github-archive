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
      end
    end
  end
end
