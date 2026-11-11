# typed: true
# frozen_string_literal: true

module GitHub
  module FaradayMiddleware
    # Faraday middleware that inserts the the X-Country header to
    # downstream services
    class CountryCode < ::Faraday::Middleware
      COUNTRY_CODE_HEADER = "X-Country"

      def call(env)
        if GitHub.context[:country_code]
          env.request_headers[COUNTRY_CODE_HEADER] = GitHub.context[:country_code]
        end

        @app.call(env)
      end
    end
  end
end
