# typed: true
# frozen_string_literal: true

require "active_support/notifications"

class VexiSubscriber
  def self.collector
    GitHub::DataCollector::Collector.get_instance(:vexi_subscriber)
  end

  sig { returns(T::Hash[Symbol, T::Boolean]) }
  def self.tested_features
    collector[:tested_features] ||= Hash.new
  end

  def self.enabled_tested_features
    tested_features.keys.select { |k| tested_features[k] }
  end

  def self.tested_feature_timings
    collector[:tested_feature_timings] ||= Hash.new { |h, feature| h[feature] = [] }
  end

  def self.total_preload_duration
    collector[:preload_duration] || 0
  end

  def self.preloaded_features
    collector[:preloaded_features] ||= Set.new
  end

  def self.collector_enabled?
    collector.enabled?
  end

  def self.total_enabled_calls
    tested_feature_timings.values.flatten.size
  end

  def self.total_enabled_duration
    tested_feature_timings.values.flatten.sum
  end

  def self.total_enabled_duration_us
    (total_enabled_duration * 1_000_000).round
  end

  def self.record_duration_event(event)
    operation = event.payload[:operation]
    measured_duration = event.payload[:measured_finish].to_f - event.payload[:measured_start].to_f

    # In case measuring the Vexi operation is interrupted by a timeout error, both start and finish might be the same value
    # To prevent skewing the results, we won't record such cases
    return if measured_duration.zero?

    case operation
    when "is_enabled"
      track_is_enabled(event.payload[:feature_flag_name], event.payload[:result], measured_duration)
    when "preload"
      track_preload(event.payload[:feature_flag_names], measured_duration)
    end
  end

  def self.hydro_stats
    features = tested_features.to_a.map do |(name, enabled)|
      {
        name: name.to_s,
        enabled: enabled,
        preloaded: self.preloaded_features.include?(name),
        durations_us: tested_feature_timings[name].map { |d| (d * 1_000_000).round },
      }
    end
    {
      tested_feature_flags: features,
      feature_flag_checks_count: self.total_enabled_calls,
      feature_flag_us: self.total_enabled_duration_us,
    }
  end

  private_class_method def self.track_is_enabled(feature_name, result, duration)
    return unless self.collector.enabled?

    tested_features[feature_name] ||= result
    tested_feature_timings[feature_name].push(duration)
  end

  private_class_method def self.track_preload(names, duration)
    return unless self.collector.enabled?

    self.preloaded_features.merge(names)
    self.collector[:preload_duration] ||= 0
    self.collector[:preload_duration] += duration
  end
end

ActiveSupport::Notifications.subscribe(/\Avexi\..+\.duration\Z/) do |event|
  VexiSubscriber.record_duration_event(event)
end
