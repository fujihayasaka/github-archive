# typed: strict
# frozen_string_literal: true

module GitHub
  module DataCollector
    class HTMLPipelineInstrumenterCollector < Collector
      set_callback :reset, :after do |collector|
        collector.pipeline_runs = 0
      end

      attributes :pipeline_runs

      sig { returns(Symbol) }
      def self.collector_name
        :html_pipeline_instrumenter_collector
      end
    end
  end
end
