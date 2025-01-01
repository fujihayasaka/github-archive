# typed: true
# frozen_string_literal: true

module GitHub
  module Limiters
    class SearchCountAnonymous < SearchCount

      DEFAULT_SEARCH_LIMIT = 500

      SEARCH_TYPE_LIMITS = {
        "code"         => 50,
        "commits"      => 50,
        "issues"       => 100,
        "users"        => 100,
        "wikis"        => 100,
        "repositories" => DEFAULT_SEARCH_LIMIT,
      }.freeze

      # Create a new global rate limiter aimed at restricting the overall volume
      # of anonymous search requests coming from multiple IP addresses. The
      # `CodesearchController` already limits anonymous search requests based on
      # a single IP; this limiter is applied to all IP addresses.
      #
      # ttl - The "time to live" for rate limiting. The default is 60 seconds.
      #
      def initialize(ttl: 60)
        super "search-count-anonymous", limit: DEFAULT_SEARCH_LIMIT, ttl: ttl
      end

      def start(request)
        set_limit(request)
        super(request)
      end

      # Set the anonymous query limit based on the search request type.
      def set_limit(request)
        type = search_type(request)
        @limit = SEARCH_TYPE_LIMITS.fetch(type, DEFAULT_SEARCH_LIMIT)
      end

      # Returns the memcache key used to track the search volume based on the
      # search request type.
      def key(request)
        return DEFAULT_SEARCH_TYPE unless request.params["type"].present?
        search_type(request)
      end

      # Anonymous users are prompted to log in if they are doing a search of
      # type `code` so we want don't want the rate limiter to get in the way of
      # prompting to sign in
      def check_limits?(request)
        if search_type(request) == "code"
          tags = Array(tags(request)).concat(["limiter:#{name}"])
          GitHub.dogstats.increment("limited.skip", tags: tags)
          return false
        end
        super(request)
      end
    end
  end
end
