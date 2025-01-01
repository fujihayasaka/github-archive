# frozen_string_literal: true
# typed: strict

require "sorbet-runtime"
require "vexi/configuration"
require "vexi/caches/in_memory"

module Vexi
  module Builders
    class CacheBuilder
      def initialize(config)
        @config = T.let(config, Configuration)
      end

      def in_memory(ttl = 30, not_found_ttl = 30)
        @config.cache_config = CacheConfig.new(Caches::InMemory.new, ttl, not_found_ttl)
      end

      def custom(custom_cache, ttl, not_found_ttl, feature_flag_key_prefix = nil, segment_key_prefix = nil)
        @config.cache_config = CacheConfig.new(custom_cache, ttl, not_found_ttl, feature_flag_key_prefix, segment_key_prefix)
      end

      def from_config(cache_config)
        @config.cache_config = cache_config
      end
    end
  end
end
