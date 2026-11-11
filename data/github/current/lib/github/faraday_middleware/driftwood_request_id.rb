# typed: true
# frozen_string_literal: true

module GitHub
  module FaradayMiddleware
    # Faraday middleware that passes the GitHub request ID to the Driftwood service.
    class DriftwoodRequestID < ::Faraday::Middleware
      GITHUB_REQUEST_ID_HEADER = "X-GitHub-Request-Id"

      def call(env)
        if GitHub.context[:request_id]
          env.request_headers[GITHUB_REQUEST_ID_HEADER] = GitHub.context[:request_id]
        end

        @app.call(env)
      end
    end
  end
end
