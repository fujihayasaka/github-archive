# typed: true
# frozen_string_literal: true

module GitHub
  module DataCollector
    class GitRPCInstrumenterCollector < Collector
      CallStats = Struct.new(:count, :time)

      set_callback :reset, :after do |collector|
        collector.rpc_time = 0
        collector.rpc_count = 0
        collector.rpc_calls = []
        collector.rpc_call_stats = Hash.new { |h, k| h[k] = CallStats.new(0, 0) }
        collector.tags = []
        collector.stats_tags = []
      end

      attributes :rpc_time, :rpc_count, :rpc_calls, :rpc_call_stats, :tags, :stats_tags

      def self.collector_name
        :gitrpc_instrumenter_collector
      end
    end
  end
end
