# typed: true
# frozen_string_literal: true

module Instrumentation
  # This class is intended to enhance a checker used with Instrumentation::QuerySubscriber to add sampling
  class SampledChecker
    # A sentinel object returned by #check to indicate to callers that
    # the execution was skipped because of sampling.
    SKIPPED_BECAUSE_SAMPLING = Class.new

    attr_reader :sample_rate

    def initialize(checker:, sample_rate:)
      @checker = checker
      @sample_rate = sample_rate
    end

    def check(**args)
      return SKIPPED_BECAUSE_SAMPLING if sample_rate < rand
      @checker.check(**args)
    end
  end
end
