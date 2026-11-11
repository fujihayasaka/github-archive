# typed: strict
# frozen_string_literal: true

class Stafftools::Copilot::CacheRefreshIntervalComponent < ApplicationComponent
  sig { returns(ActiveSupport::Duration) }
  def current_interval
    Copilot::CacheRefreshIntervalSetting.current_interval
  end

  sig { returns(String) }
  def formatted_current_interval
    seconds = interval_seconds
    return "#{seconds} #{"second".pluralize(seconds)}" if seconds < 60

    hours, remainder = seconds.divmod(3600)
    minutes = remainder / 60

    parts = []
    parts << "#{hours} #{"hour".pluralize(hours)}" if hours.positive?
    parts << "#{minutes} #{"minute".pluralize(minutes)}" if minutes.positive?
    parts.join(" ")
  end

  sig { returns(Integer) }
  def current_value
    if interval_seconds % 3600 == 0
      interval_seconds / 3600
    else
      [interval_seconds / 60, 1].max
    end
  end

  sig { returns(String) }
  def current_unit
    interval_seconds % 3600 == 0 ? "hours" : "minutes"
  end

  sig { returns(Integer) }
  def min_minutes
    Copilot::CacheRefreshIntervalSetting::MIN_INTERVAL.to_i / 60
  end

  sig { returns(Integer) }
  def max_hours
    Copilot::CacheRefreshIntervalSetting::MAX_INTERVAL.to_i / 3600
  end

  sig { returns(Symbol) }
  def feature_flag
    Copilot::CacheRefreshIntervalSetting::FEATURE_FLAG
  end

  private

  sig { returns(Integer) }
  def interval_seconds
    current_interval.to_i
  end
end
