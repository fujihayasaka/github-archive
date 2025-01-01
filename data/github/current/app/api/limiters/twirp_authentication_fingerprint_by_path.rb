# typed: true
# frozen_string_literal: true

module Api
  module Limiters
    class TwirpAuthenticationFingerprintByPath < GitHub::Limiters::MemcachedWindow
      include Api::Limiters::TwirpHelpers

      UNKNOWN_CLIENT_NAME = "unknown"

      def initialize(max:)
        super("twirp-authentication-fingerprint-by-path", limit: max)
      end

      def start(request)
        return OK unless self.class.twirp_request?(request)
        super(request)
      end

      def record_finish(request)
        return OK unless self.class.twirp_request?(request)
        increment_counter(request)
      end

      # If the request was canceled we don't want to cost the request.
      def cancel(request)
        OK
      end

      protected

      # Protected: The key is composed of the client name, authentication fingerprint,
      # and the hashed path.
      def key(request)
        hashed_path = Digest::SHA256.hexdigest(request.path_info)
        client_name = Api::Internal::Twirp.client_name_from_header(request) || UNKNOWN_CLIENT_NAME
        "#{client_name}:#{fingerprint(request)}:#{hashed_path}"
      end

      def fingerprint(request)
        Api::Middleware::RequestAuthenticationFingerprint.get(request.env).to_s
      end
    end
  end
end
