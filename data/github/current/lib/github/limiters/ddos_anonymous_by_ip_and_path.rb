# typed: true
# frozen_string_literal: true

module GitHub
  module Limiters
    # Limit anonymous requests by client IP and path
    class DDoSAnonymousByIPAndPath < MemcachedWindow
      include GitHub::Middleware::Constants
      include GitHub::Middleware::AnonymousRequest

      def initialize(limit:, ttl: 60)
        super "anon-ip-path-ddos", limit: limit, ttl: ttl, glb: true
      end

      def start(request)
        return OK unless anonymous_request?(request)
        return OK if CountAnonymousByIPAndPath::IGNORED_PATHS.match?(request.path_info)
        return OK unless FeatureFlag.vexi.enabled_or_raise?(:glb_ddos_anon_ip_path_limit) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
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
