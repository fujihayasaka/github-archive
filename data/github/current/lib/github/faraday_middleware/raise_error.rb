# typed: true
# frozen_string_literal: true

module GitHub
  module FaradayMiddleware
    # Custom Faraday RaiseError class to override the original faraday
    # response_values method which may lead to PII response headers
    # and response body leaks
    class RaiseError < Faraday::Response::RaiseError
      def response_values(env)
        { status: env.status }
      end
    end
  end
end
