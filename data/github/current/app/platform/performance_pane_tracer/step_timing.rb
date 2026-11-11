# typed: true
# frozen_string_literal: true

module Platform
  module PerformancePaneTracer
    # A StepTiming wraps some part of execution with stats.
    #
    # For field timings, it has _two_ kinds of events:
    # - Calling the resolve function of a field; OR
    # - Calling `#sync` on a returned promise.
    #
    # When the timing reflects a `#sync` call, `#lazy?` returns true.
    #
    # Corresponding timings may be matched by `#path`: matching timings
    # have the same path value, but one has `lazy: false`, the other has `lazy: true`.
    class StepTiming
      attr_reader :start_offset, :duration, :name, :path, :catalog_service
      attr_reader :gitrpc_calls, :mysql_calls, :gql_path,
        :memcached_calls_count, :memcached_calls_time,
        :redis_calls, :elastomer_calls, :mysql_cache_hits,
        :cpu_time, :allocated_objects, :allocated_objects_count, :lines

      attr_accessor :mysql_count, :mysql_time

      def initialize(start_offset:, duration:, lazy:, path:, gql_path:, name:, stats:, catalog_service:)
        @start_offset = start_offset
        @duration = duration
        @lazy = lazy
        @path = path
        @gql_path = gql_path || path
        @name = name
        @catalog_service = catalog_service
        @gitrpc_calls, @mysql_calls, @memcached_calls_count, @memcached_calls_time, @redis_calls, @elastomer_calls, @mysql_cache_hits, @cpu_time, @allocated_objects, @allocated_objects_count, @lines = stats
        @mysql_count = @mysql_calls.size
        @mysql_time = (@mysql_calls.sum(&:duration) || 0) * 1000
      end

      # @return [Boolean] True when this timing reflects `Promise#sync` time
      def lazy?
        @lazy
      end

      def primary_queries
        @_primary_queries ||= @mysql_calls.select(&:on_primary)
      end

      def n_plus1_queries
        @_n_plus1_queries ||= Platform::Tracing::Helpers::NPlusOneQueries.get(mysql_calls)
      end
    end
  end
end
