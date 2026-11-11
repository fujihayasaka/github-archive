# typed: true
# frozen_string_literal: true

# Experiment subclass for REST API Issues MySQL backend comparison experiments.
# Injects a pre-measured ES (control path) duration so published control timing
# reflects the real search latency instead of the lightweight control block execution.

module Api
  class IssuesMysqlBackendExperiment < ::GitHub::Experiment
    def initialize(name, es_ms:, es_cpu_ms: nil, &block)
      @es_ms = es_ms
      @es_cpu_ms = es_cpu_ms
      super(name, &block)
    end

    def publish(result)
      # IMPORTANT: result.payload constructs a NEW hash each time it's called.
      # Mutating result.payload then calling super would discard our mutation
      # because the base implementation calls result.payload again. So we take
      # one snapshot, modify it, and pass it directly to the class-level
      # publisher instead of calling super.
      payload = result.payload

      if (@es_ms || @es_cpu_ms) && (control = payload[:control])
        # Duplicate only the control sub-hash to avoid mutating any shared state.
        control = control.dup
        control[:duration] = @es_ms if @es_ms
        control[:cpu_time] = @es_cpu_ms if @es_cpu_ms
        payload = payload.merge(control: control)
      end
      self.class.publish(outcome: result.outcome, payload: payload)
    end
  end
end
