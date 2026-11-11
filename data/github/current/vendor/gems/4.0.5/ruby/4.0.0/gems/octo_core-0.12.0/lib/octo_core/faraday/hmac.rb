# typed: strict
# frozen_string_literal: true

module OctoCore
  module Faraday
    class HMAC < ::Faraday::Middleware
      extend T::Sig

      HMAC_AUTH_HEADER = "Request-HMAC"

      # Public: Initialize the middleware with an HMAC key
      #
      # app      - The faraday application/middlewares stack.
      # hmac_key - String HMAC secret key.
      sig { params(app: T.any(::Faraday::Middleware, ::Faraday::Adapter), hmac_key: String).void }
      def initialize(app, hmac_key)
        super(app)
        @hmac_key = T.let(hmac_key.strip, String)
      end

      sig { params(env: ::Faraday::Env).returns(::Faraday::Response) }
      def call(env)
        env[:request_headers][HMAC_AUTH_HEADER] = hmac_token
        app.call(env)
      end

      private

      sig { returns(String) }
      def hmac_token
        OctoCore::Auth::Hmac.generate_hmac(Time.now, @hmac_key)
      end
    end
  end
end
