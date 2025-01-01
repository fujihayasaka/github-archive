# typed: true
# frozen_string_literal: true

require "monolith-twirp-spokesd-core"

module Api::Internal::Twirp::Spokesd
  module Core
    module V1
      # Handler for the MonolithTwirp::Spokesd::Core::V1::UsersAPIService
      class UsersAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["spokesd"]
        handles_service MonolithTwirp::Spokesd::Core::V1::UsersAPIService

        # Public: Implementation of the GetUsers Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Spokesd::Core::V1::GetUsersRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Spokesd::Core::V1::GetUsersResponse, or a Twirp::Error.
        def get_users(req, env)
          users = User.where(id: req.user_ids.to_a)
          res_users = users.map { |u| { id: u.id, login: u.login } }
          { users: res_users }
        end
      end
    end
  end
end
