# typed: true
# frozen_string_literal: true

class McpOauth::Configuration
  def self.redirect_uri
    "#{GitHub.url}/copilot/mcp/authorization"
  end
end
