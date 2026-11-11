# typed: true
# frozen_string_literal: true

module GitHub
  module FaradayMiddleware
    # Faraday middleware that inserts the a header required to pass the
    # information that the request is coming from a staff request on to
    # downstream services.
    class StaffRequest < ::Faraday::Middleware
      STAFF_REQUEST_HEADER = "X-GitHub-Staff".freeze

      def call(env)
        if GitHub.context[:staff_request] && GitHub.context[:staff_request] == "true"
          env.request_headers[STAFF_REQUEST_HEADER] = "true"
        end

        @app.call(env)
      end
    end
  end
end
