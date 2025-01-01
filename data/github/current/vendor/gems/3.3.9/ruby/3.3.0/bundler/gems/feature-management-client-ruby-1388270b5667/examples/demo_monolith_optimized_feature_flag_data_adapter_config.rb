# frozen_string_literal: true
# typed: true

require "sorbet-runtime"
require "vexi"
require "vexi/adapters/monolith_optimized_feature_flag_data_adapter"
require "active_support"
require "active_support/notifications"
require "vexi/observability/null"
require "vexi/observability/duration_payload"
require "vexi/observability/error_payload"
require "vexi/observability/cache_hit_or_miss_payload"

# Config creates the vexi configuration
module DemoMonolithOptimizedFeatureFlagDataAdapterConfig
  extend T::Sig
  sig { returns(Vexi::Client) }
  def self.init
    Vexi.configure do |builder|
      builder.adapter.monolith_optimized_feature_flag_data_from_url("checks-key-1", "http://localhost:8010/twirp")
    end

    Vexi.instance
  end

  # Matches notifications that follow this structure "vexi.*.error"
  ActiveSupport::Notifications.subscribe(/vexi\..+\.error/) do |event|
    # payload = Vexi::Observability::ErrorPayload.new(event)
    # puts "  * Logger Example: [ERROR] operation #{payload.operation}, #{payload.exception} on feature flag #{payload.feature_flag_name}"
    # puts "  * Metrics Example: [COUNT] operation #{payload.operation}, Increment by 1"
  end

  # Matches notifications that follow this structure "vexi.*.duration"
  ActiveSupport::Notifications.subscribe(/vexi\..+\.duration/) do |event|
    # payload = Vexi::Observability::DurationPayload.new(event)
    # measured_duration_ms = (payload.measured_finish - payload.measured_start).to_f * 1000
    # puts "  * Metrics Example: [DURATION] #{payload.operation}, #{measured_duration_ms}ms for #{payload.feature_flag_name}"
  end
end
