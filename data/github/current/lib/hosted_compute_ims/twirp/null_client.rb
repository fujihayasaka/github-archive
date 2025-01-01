# typed: true
# frozen_string_literal: true

require "github/null_objects"

# If we don't set the URL and HMAC secret, we will return a null Twirp client
# that returns Twirp unavaialble response so the the UI can display a nice message to user :)
module HostedComputeIms
  module Twirp
    class NullClient < GitHub::NullObject
      def method_missing(*args, &block)
        ::Twirp::ClientResp.new(data: nil, error: unavailable_error)
      end

      private

      def unavailable_error
        ::Twirp::Error.unavailable("Hosted Compute IMS is not configured properly.")
      end
    end
  end
end
