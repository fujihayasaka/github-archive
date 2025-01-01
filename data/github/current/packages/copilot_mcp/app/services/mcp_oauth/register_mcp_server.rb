# typed: strict
# frozen_string_literal: true

class McpOauth::RegisterMcpServer
  sig { params(server_url: String, redirect_uri: String).returns(T::Hash[Symbol, T.untyped]) }
  def self.call(server_url:, redirect_uri:)
    router = McpOauth::Router.new(server_url)
    metadata = router.metadata

    raise McpOauth::Errors::ServerRegistrationError, "Missing registration_endpoint" unless metadata[:registration_endpoint]

    body = {
      redirect_uris: [redirect_uri],
      client_name: "GitHub Copilot Chat",
      grant_types: ["authorization_code"],
      response_types: ["code"]
    }

    response = McpOauth::HttpClient.post(metadata[:registration_endpoint], body)

    unless response.success?
      case response.status
      when 301, 302, 303, 307, 308
        raise McpOauth::Errors::RegistrationEndpointRedirectError,
          "MCP server registration endpoint responded with a redirect (3xx). " \
          "Registration endpoints must accept direct POST requests. Verify you are using the correct endpoint URL."
      when 403
        raise McpOauth::Errors::RegistrationAccessDeniedError,
          "Access denied to registration endpoint at #{server_url}. This server does not support dynamic client registration."
      when 404
        raise McpOauth::Errors::RegistrationEndpointNotFoundError,
          "Registration endpoint not found at #{server_url}. Please verify the server URL is correct."
      else
        raise McpOauth::Errors::ServerRegistrationError,
          "Registration failed with status #{response.status}: #{response.reason_phrase}"
      end
    end

    JSON.parse(response.body).slice("client_id", "client_secret").transform_keys(&:to_sym)
  end
end
