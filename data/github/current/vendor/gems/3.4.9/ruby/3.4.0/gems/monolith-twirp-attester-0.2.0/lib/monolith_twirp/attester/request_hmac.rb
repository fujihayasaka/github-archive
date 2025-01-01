# frozen_string_literal: true
# typed: strict

# Faraday Middleware to sign Request-HMAC headers with the HMAC key.
#
# See https://lostisland.github.io/faraday
require 'base64'
require 'openssl'
require 'faraday'
require 'sorbet-runtime'

module MonolithTwirp
  module Attester
    class RequestHMAC < Faraday::Middleware
      extend T::Sig
      ALGORITHM = T.let("sha256".freeze, String)

      # Internal: Configure the middleware instance.
      #
      # app            - A Faraday::Adapter::NetHttp instance.
      # hmac_key       - HMAC key
      sig { params(app: T.untyped, hmac_key: String).void }
      def initialize(app, hmac_key)
        super(app)

        @app       = T.let(app, T.untyped)
        @hmac_key  = T.let(hmac_key, String)
      end

      # Internal: Execute the middleware logic.
      #
      # Used by Faraday's Rack-inspired middleware stack.
      sig { params(env: T.untyped).returns(T.any(T::Array[Integer], Faraday::Response)) }
      def call(env)
        env[:request_headers]["Request-Body-HMAC"] = generate_body_hmac(@hmac_key, env[:body])
        @app.call(env)
      end

      private

      # Private: Generate the HMAC body value.
      #
      # hmac_key - the HMAC key.
      # body     - the request body.
      #
      # Returns a String.
      sig { params(hmac_key: String, body: String).returns(String) }
      def generate_body_hmac(hmac_key, body)
        hmac = OpenSSL::HMAC.digest(ALGORITHM, hmac_key, body)
        Base64.strict_encode64(hmac)
      end
    end
  end
end
