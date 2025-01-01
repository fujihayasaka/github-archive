# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module TimeoutMiddleware
      sig { returns(Float) }
      attr_accessor :timeout_middleware_timing_metrics_sample_rate
    end
  end

  extend Config::TimeoutMiddleware
end
