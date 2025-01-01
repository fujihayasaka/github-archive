# typed: true
# frozen_string_literal: true

class McpOauth::SessionMetadata
  def self.fetch!(session)
    metadata = session[:mcp_metadata]
    raise "Missing MCP metadata in session" if metadata.nil?

    metadata.with_indifferent_access
  end
end
