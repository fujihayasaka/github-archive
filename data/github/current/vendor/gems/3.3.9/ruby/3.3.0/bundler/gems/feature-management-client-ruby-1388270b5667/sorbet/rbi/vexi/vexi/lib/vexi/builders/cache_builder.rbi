# frozen_string_literal: true
# typed: strict

module Vexi
  module Builders
    class CacheBuilder
      extend T::Sig

      sig { params(config: Configuration).void }
      def initialize(config)
        @config = T.let(config, Configuration)
      end

      sig { params(ttl: Integer, not_found_ttl: Integer).void }
      def in_memory(ttl = 30, not_found_ttl = 30); end

      sig { params(custom_cache: Cache, ttl: Integer, not_found_ttl: Integer, feature_flag_key_prefix: T.nilable(String), segment_key_prefix: T.nilable(String)).void }
      def custom(custom_cache, ttl, not_found_ttl, feature_flag_key_prefix = nil, segment_key_prefix = nil); end

      sig { params(cache_config: CacheConfig).void }
      def from_config(cache_config); end
    end
  end
end
