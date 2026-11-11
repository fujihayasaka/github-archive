# typed: strict
# frozen_string_literal: true

module AzureEXP
  module V2
    module Experiments
      # Process-level in-memory cache for TAS assignment results.
      #
      # Persists across requests within the same Pitchfork worker. A returning
      # user hitting the same worker within the TTL window gets sub-µs reads
      # instead of making an external HTTPS call.
      #
      # Cache key includes all userParams so different participant combinations
      # get separate cached results. TTL-based expiry, lazy re-fetch on miss.
      #
      # Thread-safe: Pitchfork workers are single-threaded, so no mutex needed.
      # If this changes, add a Mutex around @store.
      #
      # Memcached is ruled out: the C bindings the memcached gem relies on are
      # being removed from Ruby, blocking deploys from December 2026 onward.
      # See: https://bugs.ruby-lang.org/issues/21768
      #
      # Named InMemoryCache (not just Cache) to make the storage explicit: this
      # is a per-worker Ruby Hash, not GitHub.cache/memcached or Redis. Nothing
      # is shared across workers and everything is lost on worker restart.
      #
      class InMemoryCache
        extend T::Helpers

        # Short TTL to avoid skewing experiment results with stale assignments.
        # Experiment state propagates to the exp-tas config blob within ~5 min
        # server-side; every second cached here adds to that propagation delay.
        # Keep this to a minute or two. See PR #433282 discussion.
        DEFAULT_TTL = T.let(2 * 60, Integer) # 2 minutes
        MAX_ENTRIES = T.let(10_000, Integer) # Safety cap to prevent unbounded memory growth

        # Process-level singleton. Survives across requests within one worker.
        sig { returns(AzureEXP::V2::Experiments::InMemoryCache) }
        def self.instance
          @instance ||= T.let(new, T.nilable(AzureEXP::V2::Experiments::InMemoryCache))
        end

        sig { void }
        def self.reset!
          @instance = T.let(nil, T.nilable(AzureEXP::V2::Experiments::InMemoryCache))
        end

        sig { void }
        def initialize
          @store = T.let({}, T::Hash[String, { result: AzureEXP::V2::Experiments::AssignmentResult, expires_at: Float }])
        end

        sig { params(params: T::Hash[String, T.untyped]).returns(T.nilable(AzureEXP::V2::Experiments::AssignmentResult)) }
        def get(params)
          key = cache_key(params)
          entry = @store[key]

          if entry.nil?
            GitHub.dogstats.increment("monolith.experiments.cache.miss")
            return nil
          end

          if monotonic_now > entry[:expires_at]
            @store.delete(key)
            GitHub.dogstats.increment("monolith.experiments.cache.miss", tags: ["reason:expired"])
            return nil
          end

          GitHub.dogstats.increment("monolith.experiments.cache.hit")
          entry[:result]
        end

        sig { params(params: T::Hash[String, T.untyped], result: AzureEXP::V2::Experiments::AssignmentResult, ttl: Integer).void }
        def set(params, result, ttl: DEFAULT_TTL)
          evict_if_full
          key = cache_key(params)
          @store[key] = { result: result, expires_at: monotonic_now + ttl }
        end

        sig { void }
        def clear
          @store.clear
        end

        sig { returns(Integer) }
        def size
          @store.size
        end

        private

        # Cache key is a deterministic hash of all assignment parameters.
        sig { params(params: T::Hash[String, T.untyped]).returns(String) }
        def cache_key(params)
          sorted = params.sort.map { |k, v| "#{k}=#{v.inspect}" }.join("&")
          "monolith_experiments:#{Digest::SHA256.hexdigest(sorted)}"
        end

        # Use monotonic clock to avoid issues with system clock adjustments.
        sig { returns(Float) }
        def monotonic_now
          T.cast(Process.clock_gettime(Process::CLOCK_MONOTONIC), Float)
        end

        # Prevent unbounded memory growth by evicting expired entries first,
        # then oldest entries if still over the cap.
        sig { void }
        def evict_if_full
          return if @store.size < MAX_ENTRIES

          # First pass: remove expired entries
          now = monotonic_now
          @store.reject! { |_, entry| now > entry[:expires_at] }

          # If still full, remove the oldest 10% by expiry time
          if @store.size >= MAX_ENTRIES
            to_remove = @store.size / 10
            @store.sort_by { |_, entry| entry[:expires_at] }.first(to_remove).each { |key, _| @store.delete(key) }
          end
        end
      end
    end
  end
end
