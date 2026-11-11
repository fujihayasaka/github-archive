# typed: true
# frozen_string_literal: true

module GitHub
  module FrenoInstrumenter

    class << self
      delegate :throttle_calls_by_cluster, :throttle_calls_by_cluster=, :total_waited_by_cluster, :total_waited_by_cluster=, :timeouts, :timeouts=, :timeouts_by_cluster, :timeouts_by_cluster=, :errors, :errors=, :errors_by_cluster, :errors_by_cluster=, :open_circuits_by_cluster, :open_circuits_by_cluster=,
      to: :collector
    end

    def self.collector
      GitHub::DataCollector::FrenoInstrumenterCollector.get_instance
    end

    def self.track_throttle_calls(cluster_names)
      cluster_names.each do |cluster_name|
        self.throttle_calls_by_cluster[cluster_name] += 1
      end
    end

    def self.track_throttle_wait(waited, cluster_names)
      cluster_names.each do |cluster_name|
        self.total_waited_by_cluster[cluster_name] += waited
      end
    end

    def self.track_timeouts(cluster_names)
      cluster_names.each do |cluster_name|
        self.timeouts_by_cluster[cluster_name] += 1
        self.timeouts += 1
      end
    end

    def self.track_errors(cluster_names)
      cluster_names.each do |cluster_name|
        self.errors_by_cluster[cluster_name] += 1
        self.errors += 1
      end
    end

    def self.track_circuit_open_count(cluster_names)
      cluster_names.each do |cluster_name|
        self.open_circuits_by_cluster[cluster_name] += 1
      end
    end

    def self.reset_stats
      collector.reset
    end
  end
end
