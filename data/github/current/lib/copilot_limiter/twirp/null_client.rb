# typed: true
# frozen_string_literal: true

require "github/null_objects"

module CopilotLimiter
  module Twirp
    class NullClient < GitHub::NullObject
      def method_missing(*args, &block)
        ::Twirp::ClientResp.new(data: nil, error: unavailable_error)
      end

      private

      def unavailable_error
        ::Twirp::Error.unavailable("Copilot Limiter service is not configured properly.")
      end
    end
  end
end
