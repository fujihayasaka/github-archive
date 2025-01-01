# frozen_string_literal: true
# typed: true

require "sorbet-runtime"
require_relative "demo_monolith_optimized_feature_flag_data_adapter_config"
require_relative "seed_feature_flag_hub"
require "vexi_management"
require "vexi/adapters/monolith_optimized_feature_flag_data_adapter"
require "net/http"
require "uri"
require "json"
require "socket"

# Check if the FFH local port is open
def open?(url)
  uri = URI.parse(url)
  begin
    TCPSocket.new(uri.host, uri.port).close
    true
  rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
    false
  end
end

def test_enabled_check(name, expected, actual)
  if expected == actual
    puts "PASS     #{name}: #{actual}"
  else
    puts "FAIL!    #{name}: #{actual} - expected #{expected}"
  end
end

puts open?("http://localhost:8090") ? "Verified connection is open on http://localhost:8090 to talk to the feature flag hub" : (raise StandardError,
                                                                          "Connection is closed. Look at docs.")
puts open?("http://localhost:8010") ? "Verified connection is open on http://localhost:8010" : (raise StandardError,
                                                                          "Connection is closed. Look at docs.")
# Feel free to comment create_demo_examples out once it has been loaded once
create_demo_examples

puts "Testing monolith optimized feature flag data adapter"

vexi = DemoMonolithOptimizedFeatureFlagDataAdapterConfig.init

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
test_enabled_check("feature-flag-embedded-default-segment with known actor", true,
                   vexi.enabled?("feature-flag-non-embedded-segment", "User:10"))
test_enabled_check("feature-flag-embedded-default-segment with unknown actor", false,
                   vexi.enabled?("feature-flag-non-embedded-segment", "User:999"))
test_enabled_check("feature_flag_symbol_disabled", false, vexi.enabled?(:feature_flag_symbol_disabled))
