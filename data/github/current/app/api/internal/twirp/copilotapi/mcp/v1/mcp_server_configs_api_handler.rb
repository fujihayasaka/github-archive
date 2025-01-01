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

          configs = CopilotMcp::Query.find_all_mcp_server_configs_for_user(user)
          server_configs = configs.map do |config|
            server = config.mcp_server
            server_url = server&.url
            if req.refresh && config.refresh_token.present? && config.access_token_expired?
              begin
                tokens = McpOauth::ExchangeToken.from_refresh_token(
                  server_url: server_url,
                  refresh_token: config.refresh_token,
                  client_id: T.must(server).oauth_client_id,
                  client_secret: T.must(server).oauth_client_secret
                )

                config.update_tokens!(
                  access_token: tokens[:access_token],
                  refresh_token: tokens[:refresh_token],
                  expires_in: tokens[:expires_in]
                )
              rescue McpOauth::Errors::TokenExchangeError => e
                log_data = {
                  "code.namespace": "Api::Internal::Twirp::Copilotapi::Mcp::V1::McpServerConfigsAPIHandler",
                  "code.function": "get_server_configs",
                  "error.class": e.class.name,
                  "error.message": e.message,
                  "gh.actor.id": user.id,
                  "gh.copilot.mcp.config_id": config.id
                }
                log_data["error.backtrace"] = e.backtrace if e.backtrace

                GitHub.logger.error("MCP token refresh failed", log_data)
              end
            end
            # (Potentially) encrypt the access token if the feature flag is enabled
            if FeatureFlag.vexi.enabled?("copilot_mcp_encrypt_mcp_server_access_token", user, default: false)
              access_token = Base64.strict_encode64(GitHub.dotcom_capi_simple_box.encrypt(config.access_token))
            else
              access_token = config.access_token
            end
            {
              access_token: access_token,
              mcp_server_id: config.mcp_server_id,
              mcp_server_name: config.display_name.presence || server&.name,
              mcp_server_url: server_url,
              user_id: config.user_id,
            }
          end

          { server_configs: server_configs }
        end
      end
    end
  end
end
