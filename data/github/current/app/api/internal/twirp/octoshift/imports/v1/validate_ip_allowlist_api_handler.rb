# typed: true
# frozen_string_literal: true

require "monolith-twirp-octoshift-imports"

module Api::Internal::Twirp::Octoshift
  module Imports
    module V1
      # Handler for the MonolithTwirp::Octoshift::Imports::V1::ValidateIpAllowlistAPIService
      class ValidateIpAllowlistAPIHandler < Api::Internal::Twirp::Handler
        include Helpers::ErrorHandler
        include Imports::Helpers::ModelDelay

        handles_service MonolithTwirp::Octoshift::Imports::V1::ValidateIpAllowlistAPIService
        allow_access_for :client, allowed_clients: ["octoshift"]

        # Public: Implementation of the ValidateIpAllowlist Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Octoshift::Imports::V1::ValidateIpAllowlistRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Octoshift::Imports::V1::ValidateIpAllowlistResponse, or a Twirp::Error.
        def validate_ip_allowlist(req, env)
          if req.owner_id.zero?
            return Twirp::Error.invalid_argument("must be positive integer", argument: "owner_id")
          end

          owner = replica(Organization).find_by(id: req.owner_id)
          return Twirp::Error.not_found("Owner '#{req.owner_id}' was not found.", argument: "owner_id") unless owner

          allows_octoshift = Octoshift::ValidationHelper.allows_octoshift_ips?(owner)

          { allows_ip: allows_octoshift }
        rescue Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay => error
          replication_delay_error_handler(error.delay, error.role)
        end
      end
    end
  end
end
