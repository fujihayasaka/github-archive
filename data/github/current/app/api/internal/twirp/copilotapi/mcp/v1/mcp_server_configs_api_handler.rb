# typed: true
# frozen_string_literal: true

require "monolith-twirp-copilotapi-mcp"

module Api::Internal::Twirp::Copilotapi
  module Mcp
    module V1
      class McpServerConfigsAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["copilot_api"]
        handles_service MonolithTwirp::Copilotapi::Mcp::V1::McpServerConfigsAPIService

        sig do
          params(
            req: MonolithTwirp::Copilotapi::Mcp::V1::GetServerConfigsRequest,
            env: Hash
          ).returns(T.any(Hash, Twirp::Error))
        end
        def get_server_configs(req, env)
          unless user_id = id_argument(req.user_id)
            return Twirp::Error.invalid_argument("must be non-empty", argument: "user_id")
          end

          user = User.find_by(id: user_id)
          return Twirp::Error.not_found("User not found") unless user

          configs = GetServerConfigsForUser.call(user:)

          {
            server_configs: configs.map do |config|
              server = config.mcp_server
              {
                access_token: config.access_token,
                mcp_server_id: config.mcp_server_id,
                mcp_server_name: server&.name,
                mcp_server_url: server&.url,
                user_id: config.user_id,
              }
            end
          }
        end
      end
    end
  end
end
