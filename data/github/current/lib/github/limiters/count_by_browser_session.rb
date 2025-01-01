# typed: true
# frozen_string_literal: true

require "uri"

module GitHub
  module Limiters
    # Limit requests based on browser session from the _gh_sess cookie.
    # This will uniquely identify browser sessions, authenticated or not.
    class CountByBrowserSession < MemcachedWindow
      # Gist host pattern
      GIST_HOST = %r(gist\.github)

      # A regex for paths to ignore.
      #
      # * Ignore the /contact form for support.
      # * Ignore graphs/participation paths, it's a frequently polled url and
      #   doesn't always have a referer set.
      # * Notifications header also does not have a referer for all requests.
      # * Raw paths are cheap to service, and sometimes raw static assets are
      #   linked on other websites. Ignore these too.
      # * Download assets are ignored too, as they're also cheap for the app
      #   to service.
      # * Ignore blog posts.
      IGNORED_PATHS = %r(\A/contact|/graphs/participation|/notifications/header|/raw/|/download/|\A/blog|.atom\Z)

      # Path that ends with .js
      JS_PATH = %r(\.js\Z)

      def initialize(name: "browser-session-count", limit:, ttl: 60)
        super name, limit: limit, ttl: ttl
      end

      def start(request)
        return OK if IGNORED_PATHS.match(request.path_info)
        return OK if gist_embed?(request)
        return OK unless request.env.key?("rack.session") && request.env["rack.session"]["session_id"]
        return OK if skip_same_origin_referer? && same_origin_referer?(request)
        super
      end

      def record_start(request)
        increment_counter(request)
      end

      def key(request)
        request.env["rack.session"]["session_id"]
      end

      # Does the request include a Referer header that matches the request host?
      # If so, this is a request based on static content or referred by one of
      # our pages. Examples include:
      #
      # * <poll-include-fragment> for repo participation graphs
      # * Static images linked from READMEs or rendered markdown
      # * Static images linked from wiki pages
      #
      # Returns true if referer host/
      def same_origin_referer?(request)
        return false unless request.referer.present?

        referer = URI.parse(request.referer)
        referer.host == request.host
      rescue URI::InvalidURIError
        false
      end

      # Should the limiter skip counting requests from the same host?
      def skip_same_origin_referer?
        true
      end

      # Does this request look like a gist embed?
      def gist_embed?(request)
        request.host =~ GIST_HOST && request.path_info =~ JS_PATH
      end

      # For limited requests, add session id to logs since that'd
      # normally be added later during processing and would otherwise
      # be missing in logs
      def logging_info(request)
        Hash(super).merge("user_session_id" => request.env["rack.session"]["session_id"])
      end
    end
  end
end
