# typed: true
# frozen_string_literal: true

require "monolith-twirp-octoshift-imports"

module Api::Internal::Twirp::Octoshift
  module Imports
    module V1
      # Handler for the MonolithTwirp::Octoshift::Imports::V1::IdentityAPIService
      class IdentityAPIHandler < Api::Internal::Twirp::Handler
        include Helpers::ErrorHandler
        include Helpers::ModelDelay

        allow_access_for :client, allowed_clients: ["octoshift"]
        handles_service MonolithTwirp::Octoshift::Imports::V1::IdentityAPIService

        # Public: Implementation of the FindUserIdentity Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Octoshift::Imports::V1::FindUserIdentityRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Octoshift::Imports::V1::FindUserIdentityResponse, or a Twirp::Error.
        def find_user_identity(req, env)
          if req.user_id.zero?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "user_id")
          end

          user = replica(User).find_by(id: req.user_id)
          unless user
            return Twirp::Error.not_found("User not found.", argument: "user_id", value: req.user_id.to_s)
          end

          { user: build_user_hash(user) }
        rescue Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay => error
          replication_delay_error_handler(error.delay, error.role)
        end

        private

        def build_user_hash(user)
          {
            id: user.id,
            login: user.display_login,
            name: user.name
          }
        end
      end
    end
  end
end
