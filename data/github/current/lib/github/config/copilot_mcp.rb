# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module CopilotMcp
      # Signing key used for JWT token included in OAuth requests when setting up an MCP server on
      # behalf of a user for usage in dotcom chat. See usage in:
      # app/controllers/copilot/mcp/authorization_controller.rb
      # packages/copilot_mcp/app/public/mcp_oauth/state.rb
      attr_accessor :copilot_api_mcp_oauth_jwt_hs512_token
    end
  end
  extend Config::CopilotMcp
end
