# typed: true
# frozen_string_literal: true

require "github/null_objects"

# If we don't set the URL and HMAC secret for actions-broker we will return a null Twirp client
# that returns Twirp unavaialble response so the the UI can display a nice message to user :)
module ActionsBroker
  module Twirp
    class NullClient < GitHub::NullObject
      def method_missing(*args, &block)
        ::Twirp::ClientResp.new(data: nil, error: unavailable_error)
      end

      private

      def unavailable_error
        ::Twirp::Error.unavailable("Actions Broker service is not configured properly.")
      end
    end
  end
end
