# typed: true
# frozen_string_literal: true

module GitHub
  module Limiters
    class MemcachedWindow < GitHub::Limiter
      extend T::Sig

      def initialize(name, ttl: 60, limit:, glb: false)
        super(name)
        @limit = limit
        @ttl   = ttl
        @glb  = glb
      end

      # Internal: start a request.
      sig { params(request: T.untyped).returns(State) }
      def start(request)
        if at_limit?(request)
          State.new limited: true, duration: duration, glb: @glb
        else
          record_start(request)
          OK
        end
      end

      # Internal: finish a request.
      def finish(request)
        record_finish(request)
      end

      # Internal: a request was canceled.
      def cancel(request)
        decrement_counter(request)
      end

      # Internal: a request has timed out.
      def timeout(env)
        # Use a new memcached instance because when a timeout occurs, the
        # existing memcache client can be left in an unknown state.
        with_new_memcached_instance do
          request = Rack::Request.new(env)
          record_finish(request)
        end
      end

      # Some limiters are configured multiple times. Add some tags so we can
      # tell which limit is being hit.
      def tags(request)
        Array(super) + ["limit:#{@limit}", "ttl:#{@ttl}"]
      end

      # Some limiters are configured multiple times. Add some logging keys so
      # we can tell which limit is being hit.
      def logging_info(request)
        Hash(super).merge(
          "gh.rate_limit.secondary.max" => @limit.to_s,
          "gh.rate_limit.secondary.ttl" => @ttl.to_s,
          "gh.rate_limit.secondary.key" => key(request),
        )
      end

      protected

      # Override to record counts when limiting at the beginning of a request.
      def record_start(request)
        # increment_counter(request)
      end

      # Override to record counts when limiting at the end of a request or
      # after a timeout.
      def record_finish(request)
        # increment_counter(request)
      end

      # Override to specify how much a request costs.
      def cost(request)
        1
      end

      # Override to specify when a limit is expected to reset.
      def duration
        @ttl
      end

      # Internal: has the request met or exceeded the limit?
      def at_limit?(request)
        max = limit(request)
        max > 0 && val(key(request)) >= max
      end

      def limit(request)
        fingerprint = Api::Middleware::RequestAuthenticationFingerprint.get(request.env)

        if fingerprint
          @limit * fingerprint.limit_multiplier
        else
          @limit
        end
      end

      # Internal: Increment a tracking counter.
      def increment_counter(request)
        incr(key(request), cost(request))
      end

      # Internal: Decrement a tracking counter.
      def decrement_counter(request)
        decr(key(request), cost(request))
      end

      # Internal: the memcache key to store a counter in.
      #
      # Override to provide a request-specific key.
      def key(request)
        ""
      end

      def incr(key, value)
        prefixed_key = key_prefix + key
        total = cache.incr(prefixed_key, value)
        if total.nil?
          total = value
          cache.add(prefixed_key, total.to_s, @ttl, true)
        end
        total
      end

      def decr(key, value)
        # If the key no longer exists, ignore it.
        cache.decr(key_prefix + key, value)
      end

      def val(key)
        cache.get(key_prefix + key, true).to_i
      end

      def key_prefix
        "request-limiter:#{@name}:"
      end

      def cache
        @cache ||= GitHub.cache
      end

      # Use a fresh memcached client for the duration of the given block.
      def with_new_memcached_instance(&blk)
        original_cache = cache
        begin
          @cache = GitHub.cache.clone
          yield
        ensure
          @cache = original_cache
        end
      end
    end
  end
end
