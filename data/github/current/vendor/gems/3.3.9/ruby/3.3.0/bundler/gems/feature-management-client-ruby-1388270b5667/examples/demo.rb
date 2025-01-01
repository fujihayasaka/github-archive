# frozen_string_literal: true
# typed: true

require "sorbet-runtime"
require_relative "demo_config"

def test_enabled_check(name, expected, actual)
  if expected == actual
    puts "PASS     #{name}: #{actual}"
  else
    puts "FAIL!    #{name}: #{actual} - expected #{expected}"
  end
end

puts "Testing file adapter"
vexi = DemoConfig.init
test_enabled_check("feature-flag-does-not-exist", false, vexi.enabled?("feature-flag-does-not-exist"))
test_enabled_check("feature-flag-fully-disabled", false, vexi.enabled?("feature-flag-fully-disabled"))
test_enabled_check("feature-flag-fully-enabled", true, vexi.enabled?("feature-flag-fully-enabled"))
test_enabled_check("feature-flag-100-percent-of-calls", true, vexi.enabled?("feature-flag-100-percent-of-calls"))
test_enabled_check("feature-flag-100-percent-of-actors without actor", false,
                   vexi.enabled?("feature-flag-100-percent-of-actors"))
test_enabled_check("feature-flag-100-percent-of-actors for actor", true,
                   vexi.enabled?("feature-flag-100-percent-of-actors", "User:1"))
test_enabled_check("feature-flag-embedded-default-segment with embedded actor", true,
                   vexi.enabled?("feature-flag-embedded-default-segment", "User:1"))
test_enabled_check("feature-flag-embedded-default-segment with unknown actor", false,
                   vexi.enabled?("feature-flag-embedded-default-segment", "User:999"))
test_enabled_check("feature-flag-non-embedded-segment with known actor", true,
                   vexi.enabled?("feature-flag-non-embedded-segment", "User:10"))
test_enabled_check("feature-flag-non-embedded-segment with unknown actor", false,
                   vexi.enabled?("feature-flag-non-embedded-segment", "User:999"))
test_enabled_check("feature_flag_symbol_disabled", false, vexi.enabled?(:feature_flag_symbol_disabled))
