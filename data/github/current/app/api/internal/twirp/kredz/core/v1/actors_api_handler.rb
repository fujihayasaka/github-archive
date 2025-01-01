# typed: true
# frozen_string_literal: true

require "monolith-twirp-kredz-core"

module Api::Internal::Twirp::Kredz
  module Core
    module V1
      # Handler for the MonolithTwirp::Kredz::Core::V1::ActorsAPIService
      class ActorsAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["kredz"]
        handles_service MonolithTwirp::Kredz::Core::V1::ActorsAPIService

        # Public: Implementation of the CanActorWriteSecrets Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Kredz::Core::V1::CanActorWriteSecretsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Kredz::Core::V1::CanActorWriteSecretsResponse, or a Twirp::Error.
        def can_actor_write_secrets(req, env)
          CanActorWriteSecrets.call(req)
        end
      end
    end
  end
end
