# typed: true
# frozen_string_literal: true

module GitHub
  module FaradayMiddleware
    # Faraday middleware that inserts the an header to pass the
    # request timeout to downstream services.
    class RequestTimeoutHeader < ::Faraday::Middleware
      REQUEST_TIMEOUT_HEADER = "Request-Timeout".freeze

      def initialize(app, options = {})
        super(app)
        @fudge_factor = options[:fudge_factor] || 0.0
      end

      def call(env)
        request_timeout = env.request[:timeout]
        if request_timeout && request_timeout > 0
          env.request_headers[REQUEST_TIMEOUT_HEADER] = request_timeout_header(request_timeout)
        end

        @app.call(env)
      end

      private

      # The Request-Timeout header is equivent to the request timeout with a fudge factor applied.
      def request_timeout_header(timeout)
        request_timeout = if timeout > @fudge_factor
          timeout - @fudge_factor
        else
          timeout
        end
        "%ss" % request_timeout
      end
    end
  end
end
