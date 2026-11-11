# typed: strict
# frozen_string_literal: true

module McpOauth
  module Errors
    class TokenExchangeError < StandardError
      sig { params(message_or_exception: T.any(String, Exception)).void }
      def initialize(message_or_exception = "Token exchange failed")
        case message_or_exception
        when Exception
          super("Token exchange failed: #{message_or_exception.message}")
          set_backtrace(message_or_exception.backtrace)
        else
          super(message_or_exception)
        end
      end
    end
  end
end
