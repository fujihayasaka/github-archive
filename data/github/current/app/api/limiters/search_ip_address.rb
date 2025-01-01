# typed: true
# frozen_string_literal: true

module Api
  module Limiters
    class SearchIpAddress < GitHub::Limiters::MemcachedWindow
      SEARCH_PATH = /\A(?:\/api\/v\d+)?\/search\/([^\/]+)\/?\z/i.freeze
      DEFAULT_SEARCH_LIMIT = 500
      CODE_SEARCH_LIMIT = 300
      ISSUES_SEARCH_LIMIT = 600
      REPOSITORIES_SEARCH_LIMIT = 100
      USERS_SEARCH_LIMIT = 200

      # Create a new SearchIpAddress cost-based rate limit.
      # Each IP can use up to `max` # of requests every `ttl` period.
      #
      # max - The maximum number of requests that can be used over the TTL
      #       period before rate limiting kicks in and 429 responses are returned
      # ttl - The "time to live" for rate limiting. The default is 60 seconds.
      #
      def initialize(max:, ttl: 60)
        super("search-ip-address", limit: max, ttl: ttl)
      end

      def start(request)
        set_limit(request)
        return OK unless search_request?(request)
        super(request)
      end

      def record_finish(request)
        return OK unless search_request?(request)
        GitHub.dogstats.increment("search_request.#{search_type(request)}")
        increment_counter(request)
      end

      protected

      def set_limit(request)
        @limit = search_type_limits[search_type(request)] || DEFAULT_SEARCH_LIMIT
      end

      def search_type_limits
        {
          "code" => CODE_SEARCH_LIMIT,
          "issues" => ISSUES_SEARCH_LIMIT,
          "repositories" => REPOSITORIES_SEARCH_LIMIT,
          "users" => USERS_SEARCH_LIMIT,
        }
      end

      def key(request)
        "#{search_type(request)}:#{request.ip}"
      end

      # Returns the search type extracted from the `path_info`. Returns nil if
      # the current request is not a search request.
      def search_type(request)
        if match = SEARCH_PATH.match(request.path_info)
          match[1].downcase
        end
      end

      # Returns true if the current request is using the search API.
      def search_request?(request)
        !search_type(request).nil?
      end

      # Returns true if the current request is targeting code search.
      # def code_search?(request)
      #   CODE_SEARCH_TYPE == search_type(request)
      # end
    end
  end
end
