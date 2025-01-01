# typed: strict
# frozen_string_literal: true

module CopilotMcp::Query
  # Server queries
  sig { params(attrs: T::Hash[Symbol, T.untyped]).returns(McpServer) }
  def self.new_server(attrs = {})
    McpServer.new(attrs)
  end

  sig { params(id: Integer).returns(McpServer) }
  def self.find_mcp_server(id)
    McpServer.find(id)
  end

  sig { params(name: String).returns(T.nilable(McpServer)) }
  def self.find_mcp_server_by_name(name)
    McpServer.find_by(name: name)
  end

  # Config finders (by config id)
  # NOTE: may return configs without access tokens (in-progress).
  # Only safe to call within authorization flow

  sig { params(id: Integer, user: User).returns(McpServerConfig) }
  def self.find_mcp_server_config!(id, user)
    McpServerConfig.find_by!(id: id, user_id: user.id)
  end

  sig { params(id: Integer, user: User).returns(T.nilable(McpServerConfig)) }
  def self.find_mcp_server_config(id, user)
    McpServerConfig.find_by(id: id, user_id: user.id)
  end

  sig { params(user: User, name: String).returns(T.nilable(McpServerConfig)) }
  def self.find_mcp_server_config_by_user_and_name(user:, name:)
    McpServerConfig.joins(:mcp_server).where(user_id: user.id, mcp_servers: { name: name }).first
  end

  # Installed config queries (safe, only returns configs with tokens)

  # Returns all installed MCP server configs for a given user.
  # Used in internal APIs where no filtering or pagination is needed.
  # Preloads mcp_server association to optimize query performance.
  sig { params(user: User).returns(T::Array[McpServerConfig]) }
  def self.find_all_mcp_server_configs_for_user(user)
    installed_mcp_server_configs(user)
      .includes(:mcp_server)
      .to_a
  end

  # Returns a filterable, paginatable relation of MCP server configs for a given user.
  # Used in the settings UI to search by display name or server name.
  # Includes associated MCP servers for fallback display name rendering.
  sig { params(user: User, name: T.nilable(String)).returns(ActiveRecord::Relation) }
  def self.search_mcp_server_configs_for_user(user, name: nil)
    scope = installed_mcp_server_configs(user)

    if name.present?
      search_term = "%#{name}%"
      scope = scope.where(
        "mcp_servers.name LIKE ? COLLATE utf8mb4_general_ci OR mcp_server_configs.display_name LIKE ? COLLATE utf8mb4_general_ci",
        search_term,
        search_term
      )
    end

    scope.includes(:mcp_server)
  end

  sig { params(user: User).returns(ActiveRecord::Relation) }
  private_class_method def self.installed_mcp_server_configs(user)
    # Base scope for all installed MCP server configs (i.e., those with access tokens).
    # Filters by user and joins mcp_server for downstream use (searching, eager loading).
    McpServerConfig
      .joins(:mcp_server)
      .where(user_id: user.id)
      .where.not(access_token: nil)
  end
end
