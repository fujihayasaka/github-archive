# frozen_string_literal: true
require_relative "../current_request.rb"

module GitHub
  module FaradayMiddleware
    # Faraday middleware that inserts the two headers required to pass the
    # GitHub request ID on to downstream services.
    class RequestID < ::Faraday::Middleware
      GITHUB_REQUEST_ID_HEADER = "X-GitHub-Request-Id".freeze
      GLB_VIA_HEADER = "X-GLB-Via".freeze

      def call(env)
        if DependencyGraphAPI::CurrentRequest.request_id
          env.request_headers[GITHUB_REQUEST_ID_HEADER] = DependencyGraphAPI::CurrentRequest.request_id
          env.request_headers[GLB_VIA_HEADER] = via_header
        end

        @app.call(env)
      end

      private

      # The X-GLB-Via header is composed of the caller's hostname and the Unix timestamp as a float
      def via_header
        "hostname=#{Socket.gethostname} t=#{Time.now.to_f}"
      end
    end
  end
end
