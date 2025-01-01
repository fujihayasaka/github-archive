# typed: strict
# frozen_string_literal: true

class McpServer < ApplicationRecord::Copilot
  encrypts :oauth_client_secret
end
