# typed: strict
# frozen_string_literal: true

module McpOauth
  class RevokeAndDestroy
    class RevocationEndpointMissingError < StandardError; end
    class McpServerConfigFailedError < StandardError; end

    sig { params(config: McpServerConfig, user: ::User).void }
    def self.call(config:, user:)
      server = T.must(config.mcp_server)
      router = McpOauth::Router.new(server.url)
      revocation_endpoint = router.metadata[:revocation_endpoint]
      raise RevocationEndpointMissingError, "No revocation_endpoint provided" unless revocation_endpoint

      body = {
        token: config.refresh_token,
        token_type_hint: "refresh_token",
        client_id: server.oauth_client_id,
        client_secret: server.oauth_client_secret
      }

      response = McpOauth::HttpClient.post(
        revocation_endpoint,
        body,
        content_type: "application/x-www-form-urlencoded",
      )

      GitHub.logger.info(
        "Calling revoke token for MCP OAuth",
        "code.namespace": "McpOauth::RevokeAndDestroy",
        "code.function": "call",
        "gh.copilot.mcp.oauth.server_id": server.id,
        "gh.copilot.mcp.oauth.server_url": server.url,
        "gh.copilot.mcp.oauth.response_code": response.status,
      )

      # We log the response but don't raise errors for failed revocation attempts.
      # This allows us to gather data on which MCP servers support token revocation
      # while still allowing users to delete their configurations.

      # Record uninstallation audit event before destroying the config
      config.record_event!(:uninstalled, user)

      config.destroy
    rescue Faraday::Error, Timeout::Error, JSON::ParserError, ActiveRecord::RecordNotDestroyed => e
      raise McpServerConfigFailedError, "Failed to delete MCP configuration: #{e.message}"
    end
  end
end
