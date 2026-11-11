# typed: true
# frozen_string_literal: true

module GitHub
  module Limiters
    # Limit anonymous requests by client IP and path
    class CountAnonymousByIPAndPath < MemcachedWindow
      include GitHub::Middleware::Constants
      include GitHub::Middleware::AnonymousRequest

      IGNORED_PATHS = %r(\A/billing/zuora|/billing/stripe/platform|/billing/stripe/connect|/internal/has_ghe_license_by_entra_id|/status(\.json)?\Z)

      def initialize(limit:, ttl: 60)
        super "anon-ip-path-count", limit: limit, ttl: ttl
      end

      def start(request)
        return OK unless anonymous_request?(request)
        return OK if IGNORED_PATHS.match?(request.path_info)
        return OK if allowlisted_anon_ip?(request)
        super
      end

      def allowlisted_anon_ip?(request)
        address_actor = GitHub::FlipperIpAddress.new(request.ip)
        FeatureFlag.vexi.enabled?(:ip_and_path_limiter_anon_ip_allowlist, address_actor, default: false)
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
