# typed: true
# frozen_string_literal: true

module GitHub
  module DataCollector
    class FrenoInstrumenterCollector < Collector
      set_callback :reset, :after do |collector|
        collector.throttle_calls_by_cluster = Hash.new(0)
        collector.total_waited_by_cluster = Hash.new(0)
        collector.timeouts = 0
        collector.timeouts_by_cluster = Hash.new(0)
        collector.errors = 0
        collector.errors_by_cluster = Hash.new(0)
        collector.open_circuits_by_cluster = Hash.new(0)
      end

      attributes :throttle_calls_by_cluster, :total_waited_by_cluster, :timeouts, :timeouts_by_cluster, :errors, :errors_by_cluster, :open_circuits_by_cluster

      def self.collector_name
        :freno_instrumenter_collector
      end
    end
  end
end
