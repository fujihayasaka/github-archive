# typed: true
# frozen_string_literal: true

module Platform
  module PerformancePaneTracer
    # This class keeps a running total of external calls that have been recorded by
    # the application.
    #
    # When it's initialized, it logs the initial state of a bunch of accumulators.
    # Then, when you call `#diff`, it:
    #
    # - Compares the current values of those accumulators against its own last-observed values
    # - Extracts any differences
    # - Updates its own accumulators
    # - Returns the difference since the last call
    #
    # This way, `#diff` can tell you what calls happened since the last call.
    class ExternalCallDiff
      # Read a bunch of global values to get the initial state of the system
      def initialize
        # Let's keep track of the starting values of these,
        # then we can keep an eye on how they increment over time
        @gitrpc_count = GitRPCLogSubscriber.rpc_calls.size
        @mysql_count = GitHub::MysqlInstrumenter.queries.size
        @mysql_cache_hits_count = GitHub::MysqlInstrumenter.cached_queries.size
        # Memcached::Rails doesn't give is op-level stats, but we can get this:
        # (TBH maybe we can use GitHub.tracer? But I don't think it's worth it yet)
        @memcached_count = Memcached::Rails.query_count
        @memcached_time = Memcached::Rails.query_time
        # Redis might have some queries before us
        @redis_count = Redis::Client.queries.size
        # If elastomer is tracking, both `count` and `to_a` will have the same contents
        @elastomer_count = Elastomer::QueryStats.instance.count
      end

      # Start checking for changes
      def start
        @gitrpc_count = GitRPCLogSubscriber.rpc_calls.size
        @mysql_count = GitHub::MysqlInstrumenter.queries.size
        @mysql_cache_hits_count = GitHub::MysqlInstrumenter.cached_queries.size
        @memcached_count = Memcached::Rails.query_count
        @memcached_time = Memcached::Rails.query_time
        @redis_count = Redis::Client.queries.size
        @elastomer_count = Elastomer::QueryStats.instance.count
      end

      # Diff the state of this object against global accumulators, then:
      # - Return the diff since that's what happened since we started our check
      # - Update our accumulators to reflect those changes
      # @return [Array<Object>] A bunch of random stats
      def stop
        # See if more rpc calls have been made; if so, read them and return them in the diff
        gitrpc_count_diff = GitRPCLogSubscriber.rpc_calls.size - @gitrpc_count
        gitrpc_calls = GitRPCLogSubscriber.rpc_calls[@gitrpc_count, gitrpc_count_diff]

        # See if more SQL calls have been made; diff them if so
        mysql_count_diff = GitHub::MysqlInstrumenter.queries.size - @mysql_count
        mysql_calls = GitHub::MysqlInstrumenter.queries[@mysql_count, mysql_count_diff]

        cache_hits_diff = GitHub::MysqlInstrumenter.cached_queries.size - @mysql_cache_hits_count
        new_mysql_cache_hits = GitHub::MysqlInstrumenter.cached_queries[@mysql_cache_hits_count, cache_hits_diff]

        memcached_count_diff = Memcached::Rails.query_count - @memcached_count
        memcached_time_diff = Memcached::Rails.query_time - @memcached_time

        redis_count_diff = Redis::Client.queries.size - @redis_count
        redis_calls = Redis::Client.queries[@redis_count, redis_count_diff]

        elastomer_count_diff = Elastomer::QueryStats.instance.count - @elastomer_count
        elastomer_calls = Elastomer::QueryStats.instance.to_a[@elastomer_count, elastomer_count_diff]

        [gitrpc_calls, mysql_calls, memcached_count_diff, memcached_time_diff, redis_calls, elastomer_calls, new_mysql_cache_hits]
      end
    end
  end
end
