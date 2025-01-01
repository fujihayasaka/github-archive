# typed: strict
# frozen_string_literal: true

class McpServer < ApplicationRecord::Copilot
  encrypts :oauth_client_secret
  has_many :mcp_server_configs

  # Utility method to determine transport type from URL
  sig { returns(Symbol) }
  def transport
    if url&.end_with?("/sse")
      :legacy_sse
    elsif url&.end_with?("/mcp")
      :streamable_http
    else
      :unknown
    end
  end
end
