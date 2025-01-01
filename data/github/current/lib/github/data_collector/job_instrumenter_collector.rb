# typed: true
# frozen_string_literal: true

module GitHub
  module DataCollector
    class JobInstrumenterCollector < Collector
      set_callback :reset, :after do |collector|
        collector.enqueue_time_ms = 0
        collector.enqueue_time_per_backend_ms = Hash.new(0)
        collector.enqueue_count_per_backend_ms = Hash.new(0)
        collector.enqueued = Hash.new(0)
        collector.backend_name = nil
        collector.error = nil
        collector.will_retry = nil
        collector.initial_memory_usage = nil
        collector.final_memory_usage = nil
      end

      attributes :enqueue_time_ms, :enqueue_time_per_backend_ms, :enqueue_count_per_backend_ms,
        :enqueued, :backend_name, :error, :will_retry,
        :initial_memory_usage, :final_memory_usage

      def self.collector_name
        :job_instrumenter_collector
      end
    end
  end
end
