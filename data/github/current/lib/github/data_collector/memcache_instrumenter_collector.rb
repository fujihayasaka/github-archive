# typed: true
# frozen_string_literal: true

module GitHub
  module DataCollector
    class MemcacheInstrumenterCollector < Collector
      set_callback :reset, :after do |collector|
        collector.query_count = 0
        collector.query_time = 0
        collector.query_tracing = false
      end

      attributes :query_count, :query_time, :query_tracing

      def self.collector_name
        :memcache_instrumenter_collector
      end
    end
  end
end
