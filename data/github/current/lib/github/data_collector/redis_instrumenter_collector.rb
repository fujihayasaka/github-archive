# typed: true
# frozen_string_literal: true

module GitHub
  module DataCollector
    class RedisInstrumenterCollector < Collector
      set_callback :reset, :after do |collector|
        collector.query_count = 0
        collector.query_time = 0
        collector.queries = []
        collector.track = false
      end

      attributes :query_count, :query_time, :queries, :track

      def self.collector_name
        :redis_instrumenter_collector
      end
    end
  end
end
