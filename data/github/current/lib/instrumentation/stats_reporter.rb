# typed: true
# frozen_string_literal: true

module Instrumentation
  class StatsReporter
    def time(metric, &block)
      Instrumentation.track_time(metric) do
        block.call
      end
    end
  end

  class NoOpStatsReporter
    def time(metric, &block)
      block.call
    end
  end
end
