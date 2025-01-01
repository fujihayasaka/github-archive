# typed: true
# frozen_string_literal: true

class Stafftools::Staffbar::ProjectStats < Stafftools::Staffbar::Stats
  def xhr_stats
    true
  end

  def line_profiler_enabled?
    false
  end

  def flamegraph_enabled?
    false
  end

  def allocation_tracer_enabled?
    false
  end

  def process_stat_tracked?(sym)
    return false if [:gc, :tested_features, :memcached].include?(sym)
    super(sym)
  end

  def response_time_stats
    nil
  end

  def job_stats?
    false
  end

  def exceptions?
    false
  end
end
