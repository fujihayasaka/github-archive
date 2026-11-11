# typed: true
# frozen_string_literal: true

module GitHub
  module HTMLPipelineInstrumenter
    def self.collector
      GitHub::DataCollector::HTMLPipelineInstrumenterCollector.get_instance
    end

    def self.pipeline_runs
      collector.pipeline_runs
    end

    def self.pipeline_runs=(value)
      collector.pipeline_runs = value
    end

    def self.track_pipeline_run
      collector.pipeline_runs += 1
    end

    def self.reset
      collector.reset
    end
  end
end
