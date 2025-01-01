# typed: true
# frozen_string_literal: true

module Search
  module Limiters
    autoload :Base, "search/limiters/base"
    autoload :RateLimiterBase, "search/limiters/rate_limiter_base"
    autoload :SearchElapsedTime, "search/limiters/search_elapsed_time"
    autoload :SearchTimedOut, "search/limiters/search_timed_out"

    # registry adapters for controllers and API
    autoload :Adapters, "search/limiters/adapters"
  end
end
