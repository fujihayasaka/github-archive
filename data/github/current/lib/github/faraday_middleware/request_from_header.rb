# typed: true
# frozen_string_literal: true

module GitHub
  module FaradayMiddleware
    # Faraday middleware that propagates request origin context to downstream services.
    class RequestFromHeader < ::Faraday::Middleware
      REQUEST_FROM_HEADER = "X-Request-From".freeze

      def call(env)
        request_from = GitHub.context[:from].presence || GitHub.context[:job].presence
        env.request_headers[REQUEST_FROM_HEADER] = request_from if request_from

        @app.call(env)
      end
    end
  end
end
