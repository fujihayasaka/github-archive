# typed: true
# frozen_string_literal: true

module GitHub
  module DataCollector
    class CacheInstrumenterCollector < Collector
      set_callback :reset, :after do |collector|
        collector.query_count = 0
        collector.query_time = 0
        collector.query_tracing = false
        collector.query_sets = Hash.new(0)
        collector.query_hits = Hash.new(0)
        collector.query_misses = Hash.new(0)
        collector.query_events = Array.new
        collector.track_events = false
        collector.distributed_tracing_enabled = false
      end

      attributes :query_count, :query_time, :query_tracing, :query_sets, :query_hits, :query_misses, :query_events, :track_events, :distributed_tracing_enabled

      def self.collector_name
        :cache_instrumenter_collector
      end
    end
  end
end
