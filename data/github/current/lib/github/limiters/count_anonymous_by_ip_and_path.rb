# typed: true
# frozen_string_literal: true

module GitHub
  module Limiters
    # Limit anonymous requests by client IP and path
    class CountAnonymousByIPAndPath < MemcachedWindow
      include GitHub::Middleware::Constants
      include GitHub::Middleware::AnonymousRequest

      IGNORED_PATHS = %r(\A/billing/zuora|/billing/stripe/platform|/billing/stripe/connect|/internal/has_ghe_license_by_entra_id\Z)

      def initialize(limit:, ttl: 60)
        super "anon-ip-path-count", limit: limit, ttl: ttl
      end

      def start(request)
        return OK unless anonymous_request?(request)
        return OK if IGNORED_PATHS.match?(request.path_info)
        super
      end

      def record_start(request)
        increment_counter(request)
      end

      def key(request)
        "#{request.host}-#{request.ip}-#{request.path_info}"
      end
    end
  end
end
