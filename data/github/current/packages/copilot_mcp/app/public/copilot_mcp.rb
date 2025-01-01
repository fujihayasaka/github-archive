# typed: strict
# frozen_string_literal: true

module CopilotMcp
  sig { params(id: Integer).returns(McpServer) }
  def self.find_mcp_server(id)
    McpServer.find(id)
  end

  sig { params(id: Integer, user: User).returns(McpServerConfig) }
  def self.find_mcp_server_config(id, user)
    McpServerConfig.find_by!(id: id, user_id: user.id)
  end

  sig { params(name: String).returns(T.nilable(McpServer)) }
  def self.find_mcp_server_by_name(name)
    McpServer.find_by(name: name)
  end

  sig { params(user: User, name: String).returns(T.nilable(McpServerConfig)) }
  def self.find_mcp_server_config_by_user_and_name(user:, name:)
    McpServerConfig.joins(:mcp_server).where(user_id: user.id, mcp_servers: { name: name }).first
  end
end
