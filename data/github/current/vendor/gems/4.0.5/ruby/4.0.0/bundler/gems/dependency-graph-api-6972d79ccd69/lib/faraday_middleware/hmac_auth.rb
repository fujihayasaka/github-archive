
module GitHub
  module FaradayMiddleware
    # Faraday middleware that inserts an HMAC Authentication header into requests.
    class HMACAuth < ::Faraday::Middleware
      HMAC_AUTH_HEADER = "Request-HMAC"

      # Public: Initialize the middleware with an HMAC key
      #
      # app     - The faraday application/middlewares stack.
      # options - The Hash options used to configure the middleware
      #           :hmac - The String HMAC secret key.
      def initialize(app, options = {})
        super(app)
        @hmac_key = options[:hmac_key]
      end

      def call(env)
        env.request_headers[HMAC_AUTH_HEADER] = hmac_token
        @app.call(env)
      end

      private

      def hmac_token
        return "" if @hmac_key.blank?
        timestamp = Time.now.to_i.to_s
        digest = OpenSSL::Digest::SHA256.new
        hmac = OpenSSL::HMAC.new(@hmac_key, digest)
        hmac << timestamp
        "#{timestamp}.#{hmac}"
      end
    end
  end
end
