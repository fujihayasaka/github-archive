# typed: true
# frozen_string_literal: true

module Freno
  class ReplicationDelayCacheDecorator

    # See: https://github.com/github/github/pull/76942#issuecomment-321499657
    #
    # freno runs double-sampling:
    #  * Every 0.1s is reads heartbeat from a replica.
    #  * Every 0.1s freno aggregates the lag value across all read metrics.
    #
    # What this means is that any time you check the absolute lag on replica,
    # the answer should always tell you the truth, on the pessimistic side of 0.2s.
    #
    # However, there can be network roundtrips latencies, etc.
    # And we've observed that there are a small number of times (1/200K),
    # the data was not yet replicated using a 200ms cushion. For that reason,
    # and based on results gathered after experimentation an extra 15ms
    # are added to the above 0.2s
    #
    # See https://github.com/github/github/pull/77407#issuecomment-324373676
    #
    CUSHION_FACTOR_MILLIS = 215

    attr_accessor :request
    attr_reader   :cache, :ttl, :expires_at_millis

    def initialize(cache:, ttl:, expires_at_millis:)
      @cache = cache
      @ttl = ttl
      @expires_at_millis = expires_at_millis
    end

    def perform(**kwargs)
      cache_key = "freno:replication_delay:#{kwargs[:app]}:#{kwargs[:store_name]}:v1"
      now = Timestamp.from_time(Time.now)
      dogstats_tags = [
        "cache_key:#{cache_key}"
      ]

      GitHub.dogstats.time("freno.cache.time", tags: dogstats_tags) do
        GitHub.dogstats.increment("freno.cache.called", tags: dogstats_tags)

        delay, cached_at_ts = cache.fetch(cache_key, ttl: ttl) do
          GitHub.dogstats.increment("freno.cache.miss", tags: dogstats_tags)
          [do_request(**kwargs), now]
        end

        if (now - expires_at_millis) >= cached_at_ts
          GitHub.dogstats.increment("freno.cache.expired", tags: dogstats_tags)
          delay = do_request(**kwargs)
          cache.set(cache_key, [delay, Timestamp.from_time(Time.now)], ttl)
        end

        # We have the replication delay in cache for FRENO_CACHE_EXPIRES_AT_MILLISECONDS
        # this means that we should adjust the replication delay to cushion the fluctuations
        # in replication delay for that amount of time, plus the interval at which heartbeats
        # are sent to the replicas.
        delay + (CUSHION_FACTOR_MILLIS + expires_at_millis) / 1000.to_f
      end
    end

    private

    def do_request(**kwargs)
      GitHub.dogstats.time("freno.replication_delay.duration") do
        result = request.perform(**kwargs)
        case result
        when Numeric
          result
        when Freno::Client::Result
          raise Freno::Error, result.inspect
        else
          raise Freno::Error, "unexpected result from client: #{result.inspect}"
        end
      end
    rescue # rubocop:todo Lint/RescueException
      GitHub.dogstats.increment("freno.replication_delay.errored")
      raise
    end
  end
end
