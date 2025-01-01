# typed: true
# frozen_string_literal: true

module GitHub
  module Limiters
    # This limiter is restricted to the `/search` path, and it is designed to be
    # a superclass for search related limiters. This limiter will only be
    # applied to to the `/search` path when there is a `q` query param. Limits
    # can be imposed independently on each search `type`.
    class SearchCount < MemcachedWindow
      SEARCH_PATH = /\A\/search\/?\z/i.freeze
      SEARCH_TYPES = Set.new(%w[code commits issues marketplace users wikis repositories]).freeze
      DEFAULT_SEARCH_TYPE = "repositories"

      SEARCH_INDICES = {
        "code"         => "code-search",
        "commits"      => "commits",
        "issues"       => "issues-search",
        "marketplace"  => "marketplace-search",
        "users"        => "users",
        "wikis"        => "wikis",
        "repositories" => "repos",
      }.freeze

      # name  - The unique name for the limiter
      # limit - The maximum number of requests that can be used over the TTL
      #         period before rate limiting kicks in and 429 responses are returned
      # ttl   - The "time to live" for rate limiting. The default is 60 seconds.
      #
      def initialize(name, limit:, ttl: 60)
        super name, limit: limit, ttl: ttl
      end

      def start(request)
        return OK unless check_limits?(request)
        super(request)
      end

      def record_finish(request)
        return OK unless check_limits?(request)
        increment_counter(request)
      end

      # Returns the search type as a String
      def search_type(request)
        type = request.params["type"].to_s.downcase
        return type if SEARCH_TYPES.include? type
        DEFAULT_SEARCH_TYPE
      end

      # Returns the index name tag to use when sending metrics to DataDog.
      def tags(request)
        type = search_type(request)
        super + ["index:#{SEARCH_INDICES[type]}"]
      end

      # Returns the index name key to use when sending logs to Splunk.
      def logging_info(request)
        type = search_type(request)
        super.merge(
          "gh.rate_limit.secondary.search_index" => SEARCH_INDICES[type],
        )
      end

      # We only want to check rate limits if this is a search request and if it
      # is coming from an anonymous user (not logged in).
      def check_limits?(request)
        search_request?(request) && !logged_in?(request)
      end

      # Returns true if the current request is a search request.
      def search_request?(request)
        request.path_info =~ SEARCH_PATH && request.params["q"].present?
      end

      # Returns true if the request is associated with a logged-in user.
      def logged_in?(request)
        request.cookies["logged_in"].present? && request.cookies["logged_in"] == "yes"
      end
    end
  end
end
