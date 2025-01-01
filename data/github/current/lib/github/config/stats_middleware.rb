# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module StatsMiddleware
      sig { returns(Float) }
      attr_accessor :stats_middleware_timing_metrics_sample_rate

      sig { returns(Float) }
      attr_accessor :stats_middleware_yjit_tracker_metrics_sample_rate

      sig { returns(Float) }
      attr_accessor :stats_middleware_gc_tracker_metrics_sample_rate
    end
  end

  extend Config::StatsMiddleware
end
