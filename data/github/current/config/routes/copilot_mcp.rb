# typed: true
# frozen_string_literal: true

T.bind(self, ActionDispatch::Routing::Mapper)
# Copilot MCP routes
get "/copilot/mcp/servers", to: "copilot/mcp/servers#index", as: :mcp_servers_index
post "/copilot/mcp/servers", to: "copilot/mcp/servers#create", as: :mcp_servers_create
get "/copilot/mcp/authorization/new", to: "copilot/mcp/authorization#new", as: :mcp_authorization_new
get "/copilot/mcp/authorization", to: "copilot/mcp/authorization#create", as: :mcp_authorization_create
delete "/copilot/mcp/servers/:id", to: "copilot/mcp/servers#destroy", as: :mcp_servers_destroy

# Copilot MCP settings
get "/settings/mcp", to: "settings/mcp#index", as: :mcp_settings
