# typed: true
# frozen_string_literal: true

require "github/context_caller"

module GitHub
  module FaradayMiddleware
    # Faraday middleware that inserts a header identifying the calling
    # controller action, background job, or API route. This lets downstream
    # services (e.g. configsd) attribute traffic to its origin.
    class CallerContext < ::Faraday::Middleware
      CALLER_HEADER = "X-GitHub-Caller"

      def call(env)
        if GH.feature_flag_enabled?(:configsd_caller_context)
          source, source_type = GitHub::ContextCaller.identify
          env.request_headers[CALLER_HEADER] = "#{source_type}:#{source}" unless source_type == "unknown"
        end

        @app.call(env)
      end
    end
  end
end
