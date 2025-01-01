# typed: true
# frozen_string_literal: true

class CpuTimer
  TRACKED_METRICS = %w[
    elapsed_ms
    elapsed_cpu_ms
    elapsed_idle_ms
    elapsed_thread_cpu_ms
  ].freeze

  def self.track(name, tags:)
    tracker = new(name, tags:)
    result = tracker.track { yield }
    tracker.flush
    result
  end

  def initialize(name, tags:)
    @name = name
    @tags = tags
    @trackings = Hash.new { |h, k| h[k] = [] }
  end

  def track
    timer = Timer.start
    result = yield
    timer.stop

    TRACKED_METRICS.each do |metric|
      @trackings[metric] << timer.public_send(metric)
    end

    result
  end

  def flush
    @trackings.each do |metric, values|
      GitHub.dogstats.distribution(
        "cpu_timer.#{@name}.#{metric}",
        values.sum,
        tags: @tags,
      )
    end
  end
end
