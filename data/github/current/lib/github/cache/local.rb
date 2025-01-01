# typed: false
# frozen_string_literal: true

module GitHub
  module Cache
    # Cache mixin keeps a local hash of read and written values. This can reduce
    # roundtrips to memcached when the same cache keys are read multiple times
    # within a single request or job run.
    #
    # The easiest way to enable the local cache for web requests is with a
    # normal before filter or equivalent:
    #
    #      before_action { GitHub.cache.enable_local_cache }
    #
    # The GitHub.cache.local attribute may also be assigned a Hash directly.
    #
    # Note that the local cache is disabled by default. You must call
    # enable_local_cache or assign a Hash explicitly to enable.
    module Local

      # This is a sentinel value used for remembering the fact
      # that a key that was loaded via `#get_multi` did not
      # exist on the memcached server.
      #
      # This is important because we sometimes need to distinguish
      # between a key not being set, and a key being explicitly set to `nil`.
      MISSING = Object.new.freeze

      # Call to enable the local cache for all subsequent get and get_multi
      # calls. This method should be called early in a web request or other
      # message handling cycle to reset the local cache.
      def enable_local_cache
        self.local = {}
      end

      ##
      # Rails MemCache interface overrides

      # Override get to check the local cache first and avoid network round
      # trip. If not in local cache, read from server and store in local cache.
      def get(key, raw = false)
        return super if local.nil?

        if local.key?(key)
          increment_local_hit_count
          read_local_value(key)
        else
          get_multi([key], raw)[key]
        end
      end

      def async_get(key, raw = false)
        return super if local.nil?

        if local.key?(key)
          increment_local_hit_count
          response = ::GitHub::Cache::FakeResponse.new(key: key, value: read_local_value(key), exists: !local[key].eql?(MISSING))
          return Promise.resolve(response)
        end

        super.then do |response|
          write_local_value(key, response.exist? ? response.value : MISSING)
          response
        end
      end

      # Override set to also write to local cache.
      def set(key, value, ttl = 0, raw = false)
        write_local_value(key, value) if local

        super
      end

      def async_set(key, value, ttl = 0, raw = false)
        if local
          value = Promise.resolve(value).then do |resolved_value|
            write_local_value(key, resolved_value)
            resolved_value
          end
        end

        super(key, value, ttl, raw)
      end

      # Override add to also write to local cache.
      def add(key, value, ttl = 0, raw = false)
        res = super

        if res && local
          write_local_value(key, value)
        end

        res
      end

      def async_add(key, value, ttl = 0, raw = false)
        return super if local.nil?

        super.then do |res|
          # value must have been resolved by this point, but wrap anyway
          value.then do |resolved_value|
            write_local_value(key, resolved_value) if res.stored?
            res
          end
        end
      end

      # Override delete to also remove the key from local cache.
      def delete(key)
        local.delete(key) if local
        super
      end

      def async_delete(key)
        local.delete(key) if local
        super
      end

      # Override get_multi to first read values from local cache. Values not
      # found are read with a single get_multi and set into the local cache.
      def get_multi(keys, raw = false)
        return super if local.nil?

        # read values from local cache and separate from non-local keys
        hits = {}
        misses = keys.reject do |key|
          if local.key?(key)
            increment_local_hit_count
            hits[key] = read_local_value(key) unless local[key].eql?(MISSING)
            true
          end
        end

        # read missing values from memcached, write to local cache, and merge
        if misses.any?
          cached = super(misses, raw)
          misses.each do |key|
            write_local_value(key, cached.fetch(key) { MISSING })
          end
          hits.merge!(cached)
        end

        hits
      end

      def async_get_multi(keys, raw = false)
        return super if local.nil?

        # read values from local cache and separate from non-local keys
        hits = {}
        misses = keys.reject do |key|
          if local.key?(key)
            increment_local_hit_count
            hits[key] = read_local_value(key) unless local[key].eql?(MISSING)
            true
          end
        end

        # read missing values from memcached, write to local cache, and merge
        if misses.any?
          super(misses, raw).then do |cached|
            misses.each do |key|
              write_local_value(key, cached.fetch(key) { MISSING })
            end
            hits.merge(cached)
          end
        else
          Promise.resolve(hits)
        end
      end

      def incr(key, value = 1)
        new_value = super
        write_local_value(key, new_value) if local
        new_value
      end

      def async_incr(key, value = 1)
        super.then do |response|
          write_local_value(key, response.value) if local
          response
        end
      end

      def decr(key, value = 1)
        new_value = super
        write_local_value(key, new_value) if local
        new_value
      end

      def async_decr(key, value = 1)
        super.then do |response|
          write_local_value(key, response.value) if local
          response
        end
      end

      def read_local_value(key)
        value = local[key]
        return nil if value.eql?(MISSING)
        duplicate_value(value)
      end

      def use_write_local_value_v2?
        ENV["LOCAL_WRITE_V2"] == "true"
      end

      def write_local_value(key, value)
        if use_write_local_value_v2?
          write_local_value_v2(key, value)
        else
          write_local_value_v1(key, value)
        end
      end

      def write_local_value_v1(key, value)
        local[key] = value
        if value.eql?(MISSING)
          nil
        else
          duplicate_value(value)
        end
      end

      # Writes a value to the local cache. The value is duplicated to prevent the
      # caller from modifying the value after it has been written to the local
      # cache. In the case that the value to write is the MISSING sentinel, we
      # write the value as-is to the local cache.
      def write_local_value_v2(key, value)
        value = duplicate_value(value) unless value.eql?(MISSING)
        local[key] = value
      end

      def duplicate_value(value)
        if value.respond_to?(:deep_dup)
          value.deep_dup
        else
          value.dup
        end
      rescue TypeError
        value
      end

      def local
        Thread.current[:_github_cache_local]
      end

      def local=(data)
        Thread.current[:_github_cache_local] = data
        Thread.current[:_github_cache_local_hit_count] = 0
      end

      def local_hit_count
        Thread.current[:_github_cache_local_hit_count]
      end

      def increment_local_hit_count
        Thread.current[:_github_cache_local_hit_count] += 1
      end
    end
  end
end
