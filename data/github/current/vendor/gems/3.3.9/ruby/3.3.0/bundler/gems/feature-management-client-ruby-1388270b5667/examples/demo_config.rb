# frozen_string_literal: true
# typed: true

require "sorbet-runtime"
require "vexi"
require "vexi/adapters/file_adapter"
require "vexi/adapters/in_memory_adapter"
require "vexi/caches/in_memory"
require "active_support"
require "active_support/notifications"
require "vexi/observability/null"

# Config creates the vexi configuration
module DemoConfig
  extend T::Sig
  sig { returns(Vexi::Client) }
  def self.init
    Vexi.configure do |builder|
      builder.adapter.file("#{__dir__}/feature_flags/",  "#{__dir__}/segments/")
      builder.cache.in_memory
    end

    Vexi.instance
  end

  # Matches notifications that follow this structure "vexi.*.error"
  ActiveSupport::Notifications.subscribe(/vexi\..+\.error/) do |event|
    # puts "  * Logger Example: [ERROR] operation #{payload.operation}, #{payload.exception} on feature flag #{payload.feature_flag_name}"
    # puts "  * Metrics Example: [COUNT] operation #{payload.operation}, Increment by 1"
  end

  # Matches notifications that follow this structure "vexi.*.duration"
  ActiveSupport::Notifications.subscribe(/vexi\..+\.duration/) do |event|
    # measured_duration_ms = (payload.measured_finish - payload.measured_start).to_f * 1000
    # puts "  * Metrics Example: [DURATION] #{payload.operation}, #{measured_duration_ms}ms for #{payload.feature_flag_name}"
  end
end
