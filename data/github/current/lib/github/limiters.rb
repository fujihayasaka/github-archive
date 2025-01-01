# typed: true
# frozen_string_literal: true

module GitHub
  module Limiters
    autoload :AppMiddleware,    "github/limiters/app_middleware"
    autoload :MemcachedWindow,   "github/limiters/memcached_window"
    autoload :Middleware,       "github/limiters/middleware"
    autoload :Renderer,         "github/limiters/renderer"

    autoload :ByPath,           "github/limiters/by_path"
    autoload :CountByBrowserSessionAbuse, "github/limiters/count_by_browser_session_abuse"
    autoload :CountByBrowserSession, "github/limiters/count_by_browser_session"
    autoload :CountAnonymousByIPAndPath, "github/limiters/count_anonymous_by_ip_and_path"
    autoload :DDoSAnonymousByIPAndPath, "github/limiters/ddos_anonymous_by_ip_and_path"
    autoload :ElapsedAnonymousByIP, "github/limiters/elapsed_anonymous_by_ip"
    autoload :LRU,              "github/limiters/lru"
    autoload :Simple,           "github/limiters/simple"

    autoload :SearchCount,              "github/limiters/search_count"
    autoload :SearchCountAnonymousByIp, "github/limiters/search_count_anonymous_by_ip"
  end
end
