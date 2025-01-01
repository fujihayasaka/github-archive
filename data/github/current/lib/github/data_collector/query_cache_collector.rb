# typed: true
# frozen_string_literal: true

module GitHub
  module DataCollector
    class QueryCacheCollector < Collector
      set_callback :reset, :after do |collector|
        collector.track = false
        collector.cache_hit_count = 0
        collector.cache_hits = []
        collector.skip = nil
      end

      attributes :track, :cache_hit_count, :cache_hits, :skip

      def self.collector_name
        :query_cache_collector
      end
    end
  end
end
