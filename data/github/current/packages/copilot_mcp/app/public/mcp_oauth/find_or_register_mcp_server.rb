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
      existing_server = McpServer.find_by(url: server_url)
      return existing_server if existing_server

      result = T.let(RegisterMcpServer.call(server_url: server_url), T::Hash[Symbol, T.untyped])

      Copilot::Helpers.with_write do
        McpServer.find_or_initialize_by(url: server_url).tap do |server|
          server.oauth_client_id = result[:client_id]
          server.oauth_client_secret = result[:client_secret]
          server.name = URI(server_url).host
          server.save!
        end
      end
    end
  end
end
