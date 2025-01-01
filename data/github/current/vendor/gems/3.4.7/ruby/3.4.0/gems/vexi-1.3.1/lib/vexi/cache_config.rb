# frozen_string_literal: true
#              



module Vexi
  # Vexi cache config
  class CacheConfig
    DEFAULT_FEATURE_FLAG_KEY_PREFIX = "vexi:ff:"
    DEFAULT_SEGMENT_KEY_PREFIX = "vexi:sg:"

    # Cache instance.
    attr_reader :cache

    # TTL for caching entities returned from the adapter.
    attr_reader :ttl

    # TTL for caching entities not found from adapter.
    attr_reader :not_found_ttl

    # Cache key prefix for feature flags
    attr_reader :feature_flag_key_prefix

    # Cache key prefix for segments
    attr_reader :segment_key_prefix

    def initialize(cache, ttl, not_found_ttl, feature_flag_key_prefix = nil, segment_key_prefix = nil)
      @cache =      (cache             )
      @ttl =      (ttl         )
      @not_found_ttl =      (not_found_ttl         )
      @feature_flag_key_prefix =      (feature_flag_key_prefix || DEFAULT_FEATURE_FLAG_KEY_PREFIX        )
      @segment_key_prefix =      (segment_key_prefix || DEFAULT_SEGMENT_KEY_PREFIX        )
    end
  end
end
