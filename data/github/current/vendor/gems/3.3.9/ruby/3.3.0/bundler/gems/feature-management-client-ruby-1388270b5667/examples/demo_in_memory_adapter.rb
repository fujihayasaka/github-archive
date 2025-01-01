# frozen_string_literal: true
# typed: true

require "sorbet-runtime"
require "vexi"
require "vexi/adapters/in_memory_adapter"

# This demo shows how to use the in memory adapter in disabled_by_default mode
# with some exception_feature_flags that will be enabled.
def demo_using_disabled_by_default_mode
  puts "Demoing using the in memory adapter in disabled_by_default mode"

  puts "Setting up InMemoryAdapter in DisabledByDefault mode with some example exception_feature_flags that will be enabled"
  adapter = Vexi::Adapters::InMemoryAdapter.new(
    Vexi::Adapters::InMemoryAdapterMode::DisabledByDefault,
    exception_feature_flags: %w[feature-flag-fully-enabled feature-flag-second-fully-enabled]
  )

  puts "Creating Vexi instance with the adapter"
  Vexi.configure do |builder|
    builder.adapter.custom(adapter)
  end
  vexi = Vexi.instance

  unless vexi.enabled?("feature-flag-fully-enabled") || vexi.enabled?("feature-flag-second-fully-enabled")
    raise "expected the exception_feature_flags to be enabled"
  end

  puts "The exception_feature_flags are enabled as expected"

  raise "any other feature flag should be disabled" if vexi.enabled?("foo") || vexi.enabled?("bar")

  puts "Other feature flags are disabled as expected"
end

# This demo shows how to use the in memory adapter in disabled_by_default mode
# with some exception_feature_flags that will be enabled.
def demo_using_enabled_by_default_mode
  puts "Demoing using the memory adapter in enabled_by_default mode"

  puts "Setting up InMemoryAdapter in EnabledByDefault mode with some example exception_feature_flags that will be disabled"
  adapter = Vexi::Adapters::InMemoryAdapter.new(
    Vexi::Adapters::InMemoryAdapterMode::EnabledByDefault,
    exception_feature_flags: %w[feature-flag-fully-disabled feature-flag-second-fully-disabled]
  )

  puts "Creating Vexi instance with the adapter"
  Vexi.configure do |builder|
    builder.adapter.custom(adapter)
  end
  vexi = Vexi.instance

  if vexi.enabled?("feature-flag-fully-disabled") || vexi.enabled?("feature-flag-second-fully-disabled")
    raise "expected the exception_feature_flags to be disabled"
  end

  puts "The exception_feature_flags are disabled as expected"

  raise "any other feature flag should be enabled" unless vexi.enabled?("foo") || vexi.enabled?("bar")

  puts "Other feature flags are enabled as expected"
end

# This demo shows how to modify the state of a feature flag using the in memory adapter.
# Note: This should only be as part of a test setup when running tests using the in_memory_adapter, not in production code.
def demo_with_vexi_management
  puts "Demoing using the memory adapter and changing the state of a feature flag"

  puts "Setting up InMemoryAdapter in DisabledByDefault mode "
  adapter = Vexi::Adapters::InMemoryAdapter.new(Vexi::Adapters::InMemoryAdapterMode::DisabledByDefault)

  puts "Creating Vexi instance with the adapter"
  Vexi.configure do |builder|
    builder.adapter.custom(adapter)
  end
  vexi = Vexi.instance

  feature_flag = "demo-flag"

  raise "expected the feature flag to be disabled" if vexi.enabled?(feature_flag)

  puts "The feature flag is disabled to start"

  puts "Enabling the feature flag"
  adapter.enable(feature_flag)

  raise "expected the feature flag to be enabled" unless vexi.enabled?(feature_flag)

  puts "Now the feature flag is enabled"

  puts "Disabling the feature flag"
  adapter.disable(feature_flag)

  raise "expected the feature flag to be disabled" if vexi.enabled?(feature_flag)

  puts "The feature flag is disabled again"
end

# Run demos
puts "---"
demo_using_disabled_by_default_mode
puts "---"
demo_using_enabled_by_default_mode
puts "---"
demo_with_vexi_management

# rubocop:enable Layout/LineLength
# rubocop:enable Metrics/MethodLength
# rubocop:enable Metrics/AbcSize
