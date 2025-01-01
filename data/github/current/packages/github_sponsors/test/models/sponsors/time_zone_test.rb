# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsTimeZoneTest < GitHub::TestCase
  context ".supported_names" do
    test "includes time zones from supported country" do
      assert_includes Sponsors::TimeZone.supported_names, "America/Halifax"
    end

    test "omits time zones from an unsupported country when the time zone is only in that unsupported country" do
      unsupported_country = "IR"
      refute_includes Billing::StripeConnect::Account.supported_countries, unsupported_country,
        "need a country not supported by Stripe for this test"
      time_zone_name = "Asia/Tehran"
      assert Sponsors::TimeZone.new(time_zone_name).matches_country_code?(unsupported_country),
        "need a time zone that's in the unsupported country"

      refute_includes Sponsors::TimeZone.supported_names, "Asia/Tehran",
      "expected unsupported country #{unsupported_country} to not have its time zone #{time_zone_name} included"
    end

    test "includes aliases for supported time zones" do
      supported_country = "US"
      assert_includes Billing::StripeConnect::Account.supported_countries, supported_country,
        "need a country supported by Stripe for this test"
      time_zone_name = "Central Time (US & Canada)"
      time_zone_alias = "America/Chicago"
      assert Sponsors::TimeZone.new(time_zone_name).matches_country_code?(supported_country),
        "need a time zone that's in the supported country"
      assert Sponsors::TimeZone.new(time_zone_alias).matches_country_code?(supported_country),
        "need a time zone that's in the supported country"

      result = Sponsors::TimeZone.supported_names

      assert_includes result, time_zone_name
      assert_includes result, time_zone_alias
    end
  end

  context ".names" do
    test "returns values for unsupported country" do
      unsupported_country = "IR"
      refute_includes Billing::StripeConnect::Account.supported_countries, unsupported_country,
        "need a country not supported by Stripe for this test"
      time_zone_name = "Asia/Tehran"
      assert Sponsors::TimeZone.new(time_zone_name).matches_country_code?(unsupported_country),
        "need a time zone that's in the unsupported country"

      assert_includes Sponsors::TimeZone.names(country_code: unsupported_country), time_zone_name
    end

    test "returns multiple values if relevant" do
      time_zones = Sponsors::TimeZone.names(country_code: "US")

      assert_includes time_zones, "America/Chicago"
      assert_includes time_zones, "America/New_York"
    end

    test "returns empty set for non-existent country code" do
      assert_empty Sponsors::TimeZone.names(country_code: "XX")
    end
  end

  context "#supported?" do
    test "true for supported time zone" do
      supported_country = "US"
      assert_includes Billing::StripeConnect::Account.supported_countries, supported_country,
        "need a country supported by Stripe for this test"
      time_zone_name = "America/Chicago"
      assert Sponsors::TimeZone.new(time_zone_name).matches_country_code?(supported_country),
        "need a time zone that's in the supported country"

      assert_predicate Sponsors::TimeZone.new(time_zone_name), :supported?
    end

    test "false for unsupported time zone" do
      unsupported_country = "IR"
      refute_includes Billing::StripeConnect::Account.supported_countries, unsupported_country,
        "need a country not supported by Stripe for this test"
      time_zone_name = "Asia/Tehran"
      assert Sponsors::TimeZone.new(time_zone_name).matches_country_code?(unsupported_country),
        "need a time zone that's in the unsupported country"

      refute_predicate Sponsors::TimeZone.new(time_zone_name), :supported?
    end

    test "false for non-existent time zone" do
      refute_predicate Sponsors::TimeZone.new("nonexistent_time_zone"), :supported?
    end
  end

  context "#matches_country_code?" do
    test "true when matches country code" do
      assert Sponsors::TimeZone.new("Asia/Calcutta").matches_country_code?("IN")
    end

    test "false when conflicts with country code" do
      refute Sponsors::TimeZone.new("Asia/Calcutta").matches_country_code?("US")
    end

    test "false for invalid values" do
      refute Sponsors::TimeZone.new("invalid").matches_country_code?("invalid")
    end
  end
end
