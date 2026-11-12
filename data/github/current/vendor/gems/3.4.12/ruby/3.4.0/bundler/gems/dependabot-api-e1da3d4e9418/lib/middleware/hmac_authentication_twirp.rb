# frozen_string_literal: true

module Middleware
  # Faraday middleware that inserts an HMAC Authentication header into requests.
  class HMACAuthenticationTwirp < ::Faraday::Middleware
    HMAC_AUTH_HEADER = "Request-HMAC"

    # Public: Initialize the middleware with an HMAC key
    #
    # app      - The faraday application/middlewares stack.
    # hmac_key - String HMAC secret key.
    # hmac_header - (Optional) String HTTP header to send the HMAC token in.
    def initialize(app, options = {})
      super(app)
      @hmac_key = options[:hmac_key]
      @hmac_header = options.fetch(:header, HMAC_AUTH_HEADER).freeze
    end

    def call(env)
      env.request_headers[@hmac_header] = hmac_token
      @app.call(env)
    end

    private

    def hmac_token
      return "" if @hmac_key.blank?

      timestamp = Time.now.to_i.to_s
      digest = OpenSSL::Digest.new("SHA256")
      hmac = OpenSSL::HMAC.new(@hmac_key, digest)
      hmac << timestamp
      "#{timestamp}.#{hmac}"
    end
  end
end
