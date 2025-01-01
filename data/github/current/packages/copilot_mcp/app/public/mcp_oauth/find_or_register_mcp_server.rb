# typed: strict
# frozen_string_literal: true

module McpOauth
  class FindOrRegisterMcpServer
    sig do
      params(
        server_url: String
      ).returns(McpServer)
    end
    def self.call(server_url:)
      redirect_uri = McpOauth::Configuration.redirect_uri
      self.validate_github_domain_and_name!(server_url)

      existing_server = McpServer.find_by(url: server_url, oauth_redirect_uri: redirect_uri)
      return existing_server if existing_server

      result = T.let(RegisterMcpServer.call(server_url: server_url, redirect_uri: redirect_uri), T::Hash[Symbol, T.untyped])

      Copilot::Helpers.with_write do
        McpServer.find_or_initialize_by(url: server_url, oauth_redirect_uri: redirect_uri).tap do |server|
          server.oauth_client_id = result[:client_id]
          server.oauth_client_secret = result[:client_secret]
          server.oauth_redirect_uri = redirect_uri
          server.name = URI(server_url).host
          server.save!
        end
      end

    end

    sig { params(server_url: String).void }
    def self.validate_github_domain_and_name!(server_url)
      uri = URI.parse(server_url)
      if uri.host&.match?(/(^|\.)github\.com$/)
        raise McpOauth::Errors::UnsupportedServerError.new("GitHub tool capabilities are already available in Copilot Chat.")
      end

      name = uri.host.to_s.strip.downcase
      if name == "github"
        raise McpOauth::Errors::UnsupportedServerError.new("'GitHub' is not allowed as a server name.")
      end
    end
  end
end
