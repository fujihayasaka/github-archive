# typed: strict
# frozen_string_literal: true

module McpOauth
  module Errors
    # Raised when a server doesn't support the required OAuth authentication framework
    # (e.g., missing .well-known/oauth-authorization-server endpoint)
    class UnsupportedServerError < StandardError; end
  end
end
