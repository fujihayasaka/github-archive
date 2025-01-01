# typed: true
# frozen_string_literal: true

require "test_helper"

class TimeZoneHelperTest < GitHub::TestCase
  test "#timezone_options include all TZInfo timezones" do
    assert TZInfo::DataTimezone.all.count, Codespaces::TimeZoneHelper.timezone_options.count
  end

  test "matches against ActiveSupport names" do
    timezone = Codespaces::TimeZoneHelper.get_time_zone(time_zone_name: "Pacific Time (US & Canada)")

    assert timezone
    assert_equal "America/Los_Angeles", timezone.name
  end

  test "nil when given unsupported timezone name" do
    assert_nil Codespaces::TimeZoneHelper.get_time_zone(time_zone_name: "hey")
    assert_nil Codespaces::TimeZoneHelper.get_time_zone(time_zone_name: "")
    assert_nil Codespaces::TimeZoneHelper.get_time_zone(time_zone_name: nil)
  end
end
