# typed: true
# frozen_string_literal: true
require "test_helper"

class ReminderSchedulingTest < GitHub::TestCase
  test "#timezone_options include all TZInfo timezones" do
    assert TZInfo::DataTimezone.all.count, ReminderScheduling.timezone_options.count
  end

  context "#timezone_for" do
    test "matches against TZInfo names" do
      timezone = ReminderScheduling.timezone_for("America/Vancouver")

      assert timezone
      assert_equal "America/Vancouver", timezone.name
    end

    test "matches against ActiveSupport names" do
      timezone = ReminderScheduling.timezone_for("Pacific Time (US & Canada)")

      assert timezone
      assert_equal "America/Los_Angeles", timezone.name
    end

    test "nil when given unsupported timezone name" do
      assert_nil ReminderScheduling.timezone_for("hey")
      assert_nil ReminderScheduling.timezone_for("")
      assert_nil ReminderScheduling.timezone_for(nil)
    end
  end

  context "#valid_time_zone_name?" do
    test "true with valid timezone" do
      assert ReminderScheduling.valid_time_zone_name?("America/Vancouver")
      assert ReminderScheduling.valid_time_zone_name?("UTC")
    end

    test "false with invalid timezone" do
      refute ReminderScheduling.valid_time_zone_name?("hey")
      refute ReminderScheduling.valid_time_zone_name?("")
      refute ReminderScheduling.valid_time_zone_name?(nil)
    end
  end
end
