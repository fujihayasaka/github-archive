# frozen_string_literal: true
# typed: true

require "sorbet-runtime"
require "vexi"
require "vexi_management"
require "vexi_management/adapters/in_memory_adapter"

# This demo shows how to modify the state of a feature flag using the in memory adapter and vexi_management.
# Note: This should only be as part of a test setup when running tests using the in_memory_adapter, not in production code.
def demo_with_vexi_management
  puts "Demoing using the memory adapter and changing the state of a feature flag"

  puts "> Setting up InMemoryAdapter in disabled_by_default mode "
  adapter = Vexi::Adapters::InMemoryAdapter.new(Vexi::Adapters::InMemoryAdapterMode::DisabledByDefault)

  puts "> Creating Vexi instance with the adapter"
  Vexi.configure do |builder|
    builder.adapter.custom(adapter)
  end
  vexi = Vexi.instance

  puts "> Creating the VexiManagement wrapper of the adapter"
  management_adapter = VexiManagement::Adapters::InMemoryAdapter.new(adapter)

  puts "> Creating VexiManagement instance with the adapter"
  vexi_management = VexiManagement::VexiManagement.new(management_adapter)

  feature_flag_name = :demoflag
  feature_flag = Vexi::FeatureFlag.create_boolean_feature_flag(feature_flag_name.to_s, false)

  puts "> Creating the feature flag"
  vexi_management.create(feature_flag)

  puts "> Check to see if the feature flag exists"
  raise "expected the feature flag to exist" if vexi_management.get(feature_flag_name).nil?

  raise "expected the feature flag to be disabled" if vexi.enabled?(feature_flag_name)

  puts "The feature flag is disabled to start"

  puts "> Enabling the feature flag"
  vexi_management.enable(feature_flag_name)

  raise "expected the feature flag to be enabled" unless vexi.enabled?(feature_flag_name)

  puts "The feature flag is enabled"

  puts "> Disabling the feature flag"
  vexi_management.disable(feature_flag_name)

  raise "expected the feature flag to be disabled" if vexi.enabled?(feature_flag_name)

  puts "The feature flag is disabled again"

  puts "> Enabling the feature flag to 100% of calls"
  vexi_management.enable_percentage_of_calls(feature_flag_name, 100.0)

  raise "expected the feature flag to be enabled" unless vexi.enabled?(feature_flag_name)

  puts "The feature flag is enabled"

  puts "> Deleting the feature flag"
  vexi_management.delete(feature_flag_name)

  raise "expected the feature flag to be disabled" if vexi.enabled?(feature_flag_name)

  puts "The feature flag is considered disabled after being deleted"
end

puts "---"
demo_with_vexi_management

# rubocop:enable Layout/LineLength
# rubocop:enable Metrics/MethodLength
# rubocop:enable Metrics/AbcSize
