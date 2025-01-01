# typed: strict
# frozen_string_literal: true

class McpServerConfig < ApplicationRecord::Copilot
  encrypts :code_verifier
  encrypts :access_token
  encrypts :refresh_token

  belongs_to :user, class_name: "::User"
  belongs_to :mcp_server
end
