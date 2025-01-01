# frozen_string_literal: true
# typed: strict

module Vexi
  # Vexi cache config
  class CacheConfig
    extend T::Sig
    extend T::Helpers

    include Kernel

    # Cache instance.
    sig { returns(Cache) }
    attr_reader :cache

    # TTL for caching entities returned from the adapter.
    sig { returns(Integer) }
    attr_reader :ttl

    # TTL for caching entities not found from adapter.
    sig { returns(Integer) }
    attr_reader :not_found_ttl

    # Cache key prefix for feature flags
    sig { returns(String) }
    attr_reader :feature_flag_key_prefix

    # Cache key prefix for segments
    sig { returns(String) }
    attr_reader :segment_key_prefix

    sig { params(cache: Cache, ttl: Integer, not_found_ttl: Integer, feature_flag_key_prefix: T.nilable(String), segment_key_prefix: T.nilable(String)).void }
    def initialize(cache, ttl, not_found_ttl, feature_flag_key_prefix = nil, segment_key_prefix = nil); end
  end
end
