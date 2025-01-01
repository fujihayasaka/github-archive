# typed: true
# frozen_string_literal: true

module Search
  module Limiters
    autoload :Base, "search/limiters/base"
    autoload :RateLimiterBase, "search/limiters/rate_limiter_base"
    autoload :SearchElapsedTime, "search/limiters/search_elapsed_time"

    # registry adapters for controllers and API
    autoload :SearchElapsedTimeRegistryAdapter, "search/limiters/search_elapsed_time_registry_adapter"
  end
end
