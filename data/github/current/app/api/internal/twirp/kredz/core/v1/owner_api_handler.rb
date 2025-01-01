# typed: true
# frozen_string_literal: true

require "monolith-twirp-kredz-core"

module Api::Internal::Twirp::Kredz
  module Core
    module V1
      # Handler for the MonolithTwirp::Kredz::Core::V1::OwnerAPIService
      class OwnerAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["kredz"]
        handles_service MonolithTwirp::Kredz::Core::V1::OwnerAPIService

        # Public: Implementation of the CheckOwnerExists Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Kredz::Core::V1::CheckOwnerExistsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Kredz::Core::V1::CheckOwnerExistsResponse, or a Twirp::Error.
        def check_owner_exists(req, env)
          CheckOwnerExists.call(req)
        end
      end
    end
  end
end
