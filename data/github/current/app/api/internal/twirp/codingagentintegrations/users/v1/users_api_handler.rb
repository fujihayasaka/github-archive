# typed: true
# frozen_string_literal: true

require "monolith-twirp-codingagentintegrations-users"

module Api::Internal::Twirp::Codingagentintegrations
  module Users
    module V1
      # Handler for the CodingAgentIntegrations Users API.
      class UsersAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["coding_agent_integrations"]
        handles_service MonolithTwirp::CodingAgentIntegrations::Users::V1::UsersAPIService

        # Public: Implementation of the GetUsers Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::CodingAgentIntegrations::V1::GetUsersRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::CodingAgentIntegrations::Users::V1::GetUsersResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::CodingAgentIntegrations::Users::V1::GetUsersRequest,
            env: Hash
          ).returns(T::Hash[MonolithTwirp::CodingAgentIntegrations::Users::V1::GetUsersResponse, Twirp::Error])
        end
        def get_users(req, env)
          users = User.where(id: req.ids.to_a).to_a

          res_users = users.map { |u| { id: u.id, analytics_tracking_id: u.analytics_tracking_id } }

          { users: res_users }
        end
      end
    end
  end
end
