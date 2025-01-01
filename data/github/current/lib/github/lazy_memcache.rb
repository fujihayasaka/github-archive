# typed: true
# frozen_string_literal: true

require "active_support/core_ext/object"

module GitHub
  # A memcache client that defers its work until it it flushed later.
  # The flush operation has a strict time limit since flushing normally occurs
  # in an after_response middleware where time is inherently limited.
  # This means that the QOS of sets is on a best effort basis.  Do not use this
  # API for anything that absolutely must make it to memcache, only things
  # which can be dropped if needed.
  class LazyMemcache
    module IReadOps
      extend T::Helpers
      interface!

      sig { abstract.returns(T.untyped) }
      def cache_client; end

      sig { abstract.params(key: String, value: T.untyped, ttl: Integer).returns(T.untyped) }
      def set(key, value, ttl = 0); end
    end

    include IReadOps

    class Middleware
      DEFAULT_FLUSH_LIMIT = 2 # seconds

      def initialize(app, cache_client, flush_time_limit: DEFAULT_FLUSH_LIMIT, flush_immediately: Rails.env.test?)
        @app = app
        @cache_client = cache_client
        @flush_time_limit = flush_time_limit
        @flush_immediately = flush_immediately
      end

      def call(env)
        if GitHub.after_response.enabled?
          begin
            lazy_cache = GitHub::LazyMemcache.new(
              @cache_client,
              flush_immediately: @flush_immediately,
              flush_time_limit: @flush_time_limit
            )
            GitHub.lazy_cache = lazy_cache

            GitHub.after_response.perform(:memcache) do |after_response|
              start_time = GitHub::Dogstats.monotonic_time

              flushed, skipped, errored = lazy_cache.flush!

              tags = after_response.tags.dup
              tags << if (flushed + skipped + errored) > 0
                "flushable_data_available:true"
              else
                "flushable_data_available:false"
              end

              instrument(
                elapsed: GitHub::Dogstats.duration(start_time),
                tags: tags,
                flushed: flushed,
                skipped: skipped,
                errored: errored
              )
            end

            @app.call(env)
          ensure
            GitHub.lazy_cache = nil
          end
        else
          @app.call(env)
        end
      end

      def instrument(tags:, elapsed:, flushed:, skipped:, errored:)
        GitHub.dogstats.distribution("lazy_memcache.dist.time", elapsed, tags: tags)
        if flushed > 0
          GitHub.dogstats.distribution("lazy_memcache.flushed.count", flushed, tags: tags)
        end
        if skipped > 0
          GitHub.dogstats.increment("lazy_memcache.incomplete_flush", tags: tags)
          GitHub.dogstats.distribution("lazy_memcache.incomplete_flush.requested_op_count", skipped + flushed, tags: tags)
          GitHub.dogstats.distribution("lazy_memcache.incomplete_flush.skipped_count", skipped, tags: tags)
        end
        if errored > 0
          GitHub.dogstats.increment("lazy_memcache.error_encountered", tags: tags)
          GitHub.dogstats.distribution("lazy_memcache.errored_ops.count", errored, tags: tags)
        end
      end
    end

    # The base cache client whose API we rely on (aliased as *_orig methods by
    # GitHub::Cache::WithoutMixins) is an instance of or something that quacks
    # like Memcached::Rails which has a `set` signature of:
    #
    #   def set(key, value, ttl=@default_ttl, raw=false)
    #
    # This is a bit confusing since it is a subclass of ::Memcached whose `set`
    # method has a fourth param with the opposite meaning (encode=true).  To
    # aid readability, give a name to the `true` param we pass to orig_set.
    USE_RAW_MODE = true

    # Shared behavior that is identical between the passthrough and "real"
    # LazyMemcache clients to support read operations.
    module ReadOps
      extend T::Helpers
      requires_ancestor { IReadOps }
      include Kernel

      def get(key)
        cache_client.orig_get(key, USE_RAW_MODE)
      rescue Memcached::Error
        nil # suppress memcache errors to match GitHub::Cache::Client.
      end

      def get_multi(keys)
        cache_client.orig_get_multi(keys, USE_RAW_MODE)
      rescue Memcached::Error
        {} # suppress memcache errors to match GitHub::Cache::Client.
      end

      def fetch(key, ttl = 0)
        raise ArgumentError, "want block" unless block_given?
        result = get(key)
        if result.nil?
          result = yield
          set(key, result, ttl)
          result
        else
          result
        end
      end
    end

    include ReadOps

    # A delegation wrapper for GitHub.cache that handles the same API methods
    # that this class does (currently just set). Used in contexts where
    # LazyMemcache is called out of the unicorn request cycle.
    class PassThrough
      include ReadOps
      include IReadOps

      def initialize(cache_client)
        @cache_client = cache_client
      end

      attr_reader :cache_client

      def set(key, value, ttl = 0)
        return unless value
        ::GitHub::LazyMemcache.assert_valid_args!(key, value, ttl)
        cache_client.orig_set(key, value, ttl, USE_RAW_MODE)
      rescue Memcached::Error
        nil # Ignore memcache errors just like GitHub::Cache::Client.
      end

      def clear
        cache_client.clear
      end
    end

    def self.assert_valid_args!(key, value, ttl)
      unless key.instance_of?(String)
        raise ::GitHub::LazyMemcache::IncompatibleArg.new("key: want String, got #{key.class.name}")
      end
      unless value.instance_of?(String)
        raise ::GitHub::LazyMemcache::IncompatibleArg.new("value: want String or nil, got #{value.class.name}")
      end
      unless ttl.is_a?(Numeric) || ttl.nil?
        raise ::GitHub::LazyMemcache::IncompatibleArg.new("ttl: want numeric or nil, got #{ttl.class.name}")
      end
    end

    class IncompatibleArg < ArgumentError
    end

    # A deferred memcache `set` operation.
    # NB: We use memcache in raw mode so can only handle strings.
    class SetOperation
      def initialize(key, value, ttl)
        ::GitHub::LazyMemcache.assert_valid_args!(key, value, ttl)

        @key = key
        @value = value
        @ttl = ttl
      end

      attr_reader :key, :value, :ttl
    end

    def initialize(cache_client, flush_time_limit:, flush_immediately: false)
      @cache_client = cache_client
      @flush_immediately = flush_immediately
      @flush_time_limit = flush_time_limit
      clear
    end

    attr_reader :cache_client

    BLANK_OPSET = {
      set: [].freeze
    }.freeze

    def clear
      @operations = BLANK_OPSET.deep_dup
      @in_memory_cache = Hash.new
    end

    def operation_count
      @operations.values.sum(&:count)
    end

    def get(key, *args, **kwargs)
      @in_memory_cache.fetch(key) { super }
    end

    def get_multi(keys, *args, **kwargs)
      values = @in_memory_cache.slice(*keys)
      remaining_keys = keys - values.keys

      if remaining_keys.any?
        values.merge(super(T.unsafe(remaining_keys + args), **T.unsafe(kwargs)))
      else
        values
      end
    end

    # Defer a set operation.
    def set(key, value, ttl = 0)
      return unless value
      if @flush_immediately
        begin
          cache_client.orig_set(key, value, ttl, USE_RAW_MODE)
        rescue Memcached::Error
          nil # suppress memcache errors to match GitHub::Cache::Client.
        end
      else
        operation = SetOperation.new(key, value, ttl)
        @operations[:set] << operation
        @in_memory_cache[key] = value
      end
    end

    # Transmit all buffered data to memcache. If we're out of time, just give
    # up since we explicitly have a best effort QOS.
    def flush!
      flushed = 0
      errored = 0
      GitHub::SafeTimer.timeout(@flush_time_limit) do |timer|
        @operations[:set].each do |operation|
          break if timer.expired?
          begin
            cache_client.orig_set(operation.key, operation.value, operation.ttl, USE_RAW_MODE)
            flushed += 1
          rescue Memcached::Error
            errored += 1
            next # Ignore memcache errors just like GitHub::Cache::Client.
          end
        end
      end
      skipped = @operations[:set].size - flushed
      clear # wipe @operations
      [flushed, skipped, errored]
    end
  end
end
