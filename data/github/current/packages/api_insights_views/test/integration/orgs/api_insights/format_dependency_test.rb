# typed: true
# frozen_string_literal: true

require "test_helper"

module Orgs
  module ApiInsights
    class FormatDependencyTest < GitHub::TestCase
      fixtures do
        @user = create(:user)
      end

      setup do
        @object = Object.new
        @object.extend(Orgs::ApiInsights::FormatDependency)
      end

      context "format_time" do
        test "format_time_long in UTC" do
          User.any_instance.stubs(:time_zone).returns(ActiveSupport::TimeZone["America/Los_Angeles"])
          travel_to "2024-10-01 02:12:34 PDT" do
            assert_equal "October 01, 2024 9:12 AM UTC", @object.format_time_long(time: Time.now, user: @user, local_time: false)
          end
        end

        test "format_time_long in local" do
          User.any_instance.stubs(:time_zone).returns(ActiveSupport::TimeZone["America/Los_Angeles"])
          travel_to "2024-10-01 02:12:34 PDT" do
            assert_equal "October 01, 2024 2:12 AM PDT", @object.format_time_long(time: Time.now, user: @user, local_time: true)
          end
        end

        test "format_time_short in UTC" do
          User.any_instance.stubs(:time_zone).returns(ActiveSupport::TimeZone["America/Los_Angeles"])
          travel_to "2024-10-01 02:12:34 PDT" do
            assert_equal "Oct 1 9:12 AM", @object.format_time_short(time: Time.now, user: @user, local_time: false)
          end
        end

        test "format_time_short in local" do
          User.any_instance.stubs(:time_zone).returns(ActiveSupport::TimeZone["America/Los_Angeles"])
          travel_to "2024-10-01 02:12:34 PDT" do
            assert_equal "Oct 1 2:12 AM", @object.format_time_short(time: Time.now, user: @user, local_time: true)
          end
        end

        test "get_time_zone_string in UTC" do
          User.any_instance.stubs(:time_zone).returns(ActiveSupport::TimeZone["America/Los_Angeles"])
          travel_to "2024-10-01 02:12:34 PDT" do
            assert_equal "UTC", @object.get_time_zone_string(user: @user, local_time: false)
          end
        end

        test "get_time_zone_string in local" do
          User.any_instance.stubs(:time_zone).returns(ActiveSupport::TimeZone["Europe/Lisbon"])
          travel_to "2024-10-01 02:12:34 PDT" do
            assert_equal "WEST", @object.get_time_zone_string(user: @user, local_time: true)
          end
        end

        test "round_to_human" do
          assert_equal "199", @object.round_to_human(199)
          assert_equal "50k", @object.round_to_human(50_001)
          assert_equal "2.1m", @object.round_to_human(2_123_456)
          assert_equal "3.6b", @object.round_to_human(3_567_890_123)
        end

        test "human_readable_duration_to_seconds" do
          assert_equal 60, @object.human_readable_duration_to_seconds("1m")
          assert_equal 60 * 7, @object.human_readable_duration_to_seconds("7m")

          assert_equal 3600, @object.human_readable_duration_to_seconds("1h")
          assert_equal 3600 * 3, @object.human_readable_duration_to_seconds("3h")
          assert_equal 86400, @object.human_readable_duration_to_seconds("1d")
          assert_equal 86400 * 5, @object.human_readable_duration_to_seconds("5d")
        end
      end
    end
  end
end
