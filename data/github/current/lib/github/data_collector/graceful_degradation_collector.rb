# typed: true
# frozen_string_literal: true

module GitHub
  module DataCollector
    class GracefulDegradationCollector < Collector
      set_callback :reset, :after do |collector|
        collector.handled_exceptions = []
        collector.unhandled_exception = nil
      end

      attributes :handled_exceptions, :unhandled_exception

      def self.collector_name
        :graceful_degradation_collector
      end
    end
  end
end
