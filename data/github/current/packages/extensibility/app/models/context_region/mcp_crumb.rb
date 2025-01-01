# typed: strict
# frozen_string_literal: true

module ContextRegion
  class McpCrumb < Crumb
    sig { override.returns(String) }
    def label
      "MCP Registry"
    end

    sig { override.returns(T.nilable(Symbol)) }
    def path_name
      :mcp_registry_path
    end
  end
end
