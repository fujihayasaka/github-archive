# typed: true
# frozen_string_literal: true

module GitHub
  module Limiters
    class SearchCountAnonymousByIp < SearchCount

      IGNORED_PATHS = %r(\A/billing/zuora|/billing/stripe/platform|/billing/stripe/connect|/internal/has_ghe_license_by_entra_id|/status(\.json)?\Z)

      # Create a new rate limiter aimed at restricting of anonymous search
      # requests coming from a single IP address.
      #
      # limit - The maximum number of requests that can be used over the TTL
      #         period before rate limiting kicks in and 429 responses are returned
      # ttl   - The "time to live" for rate limiting. The default is 60 seconds.
      #
      def initialize(limit:, ttl: 60)
        super "search-count-anonymous-by-ip", limit: limit, ttl: ttl
      end

      def start(request)
        return OK if IGNORED_PATHS.match?(request.path_info)
        super
      end

      def record_finish(request)
        return if IGNORED_PATHS.match?(request.path_info)
        super
      end

      # Returns the memcache key used to track the search volume based on the IP
      # address of the anonymous request.
      def key(request)
        "#{search_type(request)}:#@ttl:#{request.ip}"
      end
    end
  end
end
