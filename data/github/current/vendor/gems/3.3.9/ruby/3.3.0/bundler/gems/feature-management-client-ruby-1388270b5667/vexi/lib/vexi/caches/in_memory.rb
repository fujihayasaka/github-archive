# frozen_string_literal: true
# typed: strict

require "sorbet-runtime"
require "zache"
require "vexi/cache"

module Vexi
  module Caches
    # Public: InMemory Cache definition.
    class InMemory
      include Cache

      def initialize
        super()
        @cache = T.let(Zache.new, Zache)
      end

      def mget(keys)
        entities = T.let([], T::Array[T.untyped])
        keys.each do |key|
          entities << @cache.get(key)
        rescue StandardError
          next
        end

        entities
      end

      def get(key)
        @cache.get(key)
      rescue StandardError
        nil
      end

      def mset(key_value_pairs, lifetime)
        effective_lifetime = convert_lifetime(lifetime)
        key_value_pairs.each do |(key, value)|
          @cache.put(key, value, lifetime: effective_lifetime)
        end
      end

      def set(key, value, lifetime)
        @cache.put(key, value, lifetime: convert_lifetime(lifetime))
      end

      def cache_name
        "in_memory"
      end

      private

      def convert_lifetime(lifetime)
        # Cache::TTL_NEVER_EXPIRE means infinite lifetime, but Zache doesn't support that so instead it just uses a huge number that is effectively never going to expire
        lifetime == Cache::TTL_NEVER_EXPIRE ? 2**32 : lifetime
      end
    end
  end
end
