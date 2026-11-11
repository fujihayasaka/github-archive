# typed: false
# frozen_string_literal: true

require "github/dogstats"
require "github/stats"

module GitHub
  module Cache
    # Methods available on GitHub::Cache::Client (GitHub.cache) that extend the basic
    # Rails memcache interface with convenience methods. This is a mixin because
    # we need to attach it to live clients and the fake memcache interface used
    # in test environments.
    module Utils
      # Handles the common case of fetching a value or running a block and
      # setting the result when not already cached. This is heavily inspired by
      # cache_fu's cache(key, &block) form.
      #
      # key     - The cache key to get/set.
      # options - Hash of options.
      #           :ttl       => Integer time-to-live value.
      #           :force     => Force the value to be recached.
      #           :raw       => Do not marshal cache value.
      #           :stats_key => Record timing and hit/miss stats under this key.
      # block   - Called when the value is not cached. If not given, no new
      #           value is written to cache.
      #
      # Returns the cached value or the result of the block.
      def fetch(key, options = {})
        options = { force: !!options } if !options.is_a?(Hash)
        write_cache = options[:force]
        stats_key = options[:stats_key]

        start = GitHub::Dogstats.monotonic_time if stats_key

        if !write_cache
          cache_result = get_multi([key], options[:raw])
          cache_value = cache_result[key]
          write_cache = !cache_result.key?(key)
        end

        if write_cache && block_given?
          cache_value = yield
          set(key, cache_value, (options[:ttl] || 0), options[:raw])
        end

        if stats_key
          subkey = if options[:force]
            "force"
          elsif write_cache
            "miss"
          else
            "hit"
          end

          tags = ["type:#{subkey}"]
          if stats_tags = options[:stats_tags]
            tags.concat(stats_tags)
          end
          GitHub.dogstats.timing_since(stats_key, start, tags: tags)
        end

        cache_value
      end

      # This is the same as 'fetch', but async. Using this opportunity to make
      # it clear what this function actually does, because 'fetch' does not
      # describe that it caches on a miss. This also makes this function have
      # a more descriptive/unique name that allows it to be allow-listed in
      # DontPassBlockToAsyncMethod.
      #
      # key     - The cache key to get/set.
      # options - Hash of options.
      #           :ttl       => Integer time-to-live value.
      #           :force     => Force the value to be recached.
      #           :raw       => Do not marshal cache value.
      #           :stats_key => Record timing and hit/miss stats under this key.
      # block   - Called when the value is not cached. If not given, no new
      #           value is written to cache. Should return a value to cache,
      #           or a promise that eventually resolves to the value to cache.
      #
      # Returns a promise resolving to the cached value or the result of the block.
      def async_get_or_cache(key, options = {}, &block)
        options = { force: !!options } if !options.is_a?(Hash)
        force_write = options[:force]
        stats_key = options[:stats_key]

        start = GitHub::Dogstats.monotonic_time if stats_key

        existing_value = if force_write
          Promise.resolve(::GitHub::Cache::FakeResponse.new(key: key, value: nil, exists: false))
        else
          async_get(key, options[:raw])
        end

        existing_value.then do |response|
          value_promise = if response.exist?
            Promise.resolve(response.value)
          else
            safe_value = Promise.resolve(true).then { block.call } # catch exceptions
            safe_value.then do |new_value|
              async_set(key, new_value, (options[:ttl] || 0), options[:raw]).then { new_value }
            end
          end

          value_promise.then do |value|
            if stats_key
              subkey = if options[:force]
                "force"
              elsif !response.exist?
                "miss"
              else
                "hit"
              end

              tags = ["type:#{subkey}"]
              if stats_tags = options[:stats_tags]
                tags.concat(stats_tags)
              end
              GitHub.dogstats.timing_since(stats_key, start, tags: tags)
            end

            value
          end
        end
      end

      # Check if a value exists in the cache.
      #
      # key - The String cache key to check.
      # options - ignored, but needed by rails `fragment_exist?`
      #
      # Returns true if the value exists in cache, false if not.
      def exist?(key, options = nil)
        if key.class == Array
          normalized_key = key.join(":")
        else
          normalized_key = key
        end
        get_multi([normalized_key]).key?(normalized_key)
      end

      def async_exist?(key, options = nil)
        async_get(key).then do |response|
          response.exist?
        end
      end

      ##
      # Rails MemCacheStore interface compatibility

      def read(key, options = nil)
        raw = (options && options[:raw]) || false
        key = key.to_s.tr(" ", "_")
        get(key, raw)
      end

      def write(key, value, options = nil)
        method = (options && options[:unless_exist]) ? :add : :set
        ttl = (options && (options[:ttl] || options[:expires_in])) || 0
        raw = (options && options[:raw]) || false
        value = value.to_s if raw
        key = key.to_s.tr(" ", "_")
        send(method, key, value, ttl, raw)
      end
    end
  end
end
