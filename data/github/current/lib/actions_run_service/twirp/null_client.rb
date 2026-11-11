# typed: true
# frozen_string_literal: true

require "github/null_objects"

# If we don't set the URL for actions-run-service we will return a null Twirp client
# that returns Twirp unavaialble response so the the UI can display a nice message to user :)
module ActionsRunService
  module Twirp
    class NullClient < GitHub::NullObject
      def method_missing(*args, &block)
        ::Twirp::ClientResp.new(data: nil, error: unavailable_error)
      end

      private

      def unavailable_error
        ::Twirp::Error.unavailable("Actions Run Service is not configured properly.")
      end
    end
  end
end
