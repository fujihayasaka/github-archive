# frozen_string_literal: true

# Bring in base cache configuration
require "github/config/memcache"

# Added to fragment and action cache key prefixes by Rails. useful for
# rev'ing only fragment caches.
ENV["RAILS_CACHE_ID"] = "v8"

# Point the cache logger to GitHub::Logger if possible
GitHub.cache.logger = GitHub::Logger if GitHub.cache.respond_to?(:logger=)

T_5_MINUTES = 300
