# typed: true
# frozen_string_literal: true

module Instrumentation
  class SampledSubscriber
    # A sentinel object returned by #check to indicate to callers that
    # the execution was skipped because of sampling.
    SKIPPED_BECAUSE_SAMPLING = Class.new

    attr_reader :sample_rate

    def initialize(executable:, sample_rate:)
      @executable = executable
      @sample_rate = sample_rate
    end

    def call(*args)
      return SKIPPED_BECAUSE_SAMPLING if sample_rate < rand
      @executable.call(*args)
    end
  end
end
