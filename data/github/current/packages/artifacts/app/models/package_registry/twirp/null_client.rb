# typed: true
# frozen_string_literal: true

require "github/null_objects"

# If package registry configuration has not been set for a GitHub install, we use a
# null client failsover any calls as a Twirp unavailable response so the UI
# behaves as expected.
module PackageRegistry
  module Twirp
    class NullClient < GitHub::NullObject
      def method_missing(*args, &block)
        ::Twirp::ClientResp.new(data: nil, error: unavailable_error)
      end

      private

      def unavailable_error
        ::Twirp::Error.unavailable("PackageRegistry service is not configured properly.")
      end
    end
  end
end
