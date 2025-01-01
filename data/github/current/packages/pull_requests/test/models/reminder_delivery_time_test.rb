# typed: true
# frozen_string_literal: true

require "test_helper"

class ReminderDeliveryTimeTest < GitHub::TestCase
  include GitHub::LoggerHelper

  setup do
    @org = create(:organization)
    make_trusted_oauth_apps_owner
    @slack_integration = create(:slack_integration)
    @slack_installation = make_integration_installation(
      integration: @slack_integration,
      target: @org,
    )
  end

  context "#set_next_delivery_at" do
    test "sets next_delivery_at on create" do
      delivery_time = build(:reminder_delivery_time, remindable: @org)

      assert_nil delivery_time.next_delivery_at
      delivery_time.save!
      refute_nil delivery_time.next_delivery_at
    end

    test "log is emitted when flag is enabled for a broken time zone" do
      enable_feature_flag(:schedule_reminders_time_zone_correction)

      reminder = Reminder.new(time_zone_name: "US/Pacific-New")
      delivery_time = ReminderDeliveryTime.new(day: "Saturday", time: "9:00 AM", schedulable: reminder)

      travel_to Time.parse("2000-01-02T00:00Z") # It's a Sunday
      expected = Time.parse("2000-01-08T09:00Z") # Next Saturday

      expected_log = {
        "Body" => "Time zone correction",
        "gh.scheduled_reminders.timezone" => "US/Pacific-New",
        "gh.scheduled_reminders.remindable.type" => "",
        "gh.scheduled_reminders.remindable.id" => ""
      }
      assert_logged(**expected_log) do
        delivery_time.set_next_delivery_at
      end
    end

    test "sets next_delivery_at based on current time" do
      reminder = Reminder.new(time_zone_name: "UTC")
      delivery_time = ReminderDeliveryTime.new(day: "Saturday", time: "9:00 AM", schedulable: reminder)

      travel_to Time.parse("2000-01-02T00:00Z") # It's a Sunday
      expected = Time.parse("2000-01-08T09:00Z") # Next Saturday

      delivery_time.set_next_delivery_at

      assert_equal expected, delivery_time.next_delivery_at
    end

    test "raises error when time_zone_name is not supported", skip_if_feature_enabled: :schedule_reminders_time_zone_correction  do
      reminder = Reminder.new(time_zone_name: "SystemV/PST8")
      delivery_time = ReminderDeliveryTime.new(day: "Saturday", time: "9:00 AM", schedulable: reminder)

      travel_to Time.parse("2000-01-02T00:00Z") # It's a Sunday

      assert_raises(RuntimeError) {  delivery_time.set_next_delivery_at }
    end

    test "corrects time_zone_name when schedule_reminders_time_zone_correction is enabled",  feature_enabled: :schedule_reminders_time_zone_correction  do
      reminder = Reminder.new(time_zone_name: "SystemV/PST8")
      delivery_time = ReminderDeliveryTime.new(day: "Saturday", time: "9:00 AM", schedulable: reminder)

      travel_to Time.parse("2000-01-02T00:00Z") # It's a Sunday
      expected = Time.parse("Sat, 08 Jan 2000 17:00:00.000000000 UTC +00:00") # Next Saturday at 9:00 AM PST which is 17:00 UTC

      delivery_time.set_next_delivery_at

      assert_equal expected, delivery_time.next_delivery_at
    end
  end

  context "#update_next_delivery_at" do
    test "persists next delivery time when next_delivery_at is in the past" do
      delivery_time = create(:reminder_delivery_time, remindable: @org)
      travel_to(delivery_time.next_delivery_at + 1.second)
      next_delivery_time = delivery_time.calculate_next_delivery_time

      assert_changes -> { delivery_time.reload.next_delivery_at }, to: next_delivery_time do
        delivery_time.update_next_delivery_at
      end
    end

    test "does nothing when next_delivery_at is in the future" do
      delivery_time = create(:reminder_delivery_time, remindable: @org)
      travel_to(delivery_time.next_delivery_at - 1.hour)

      assert_no_changes -> { delivery_time.reload.next_delivery_at } do
        delivery_time.update_next_delivery_at
      end
    end
  end

  context ".upcoming" do
    test "returns records whose next delivery is within 10 minutes" do
      upcoming = [
        create(:reminder_delivery_time, remindable: @org, next_delivery_at: 1.year.ago),
        create(:reminder_delivery_time, remindable: @org, next_delivery_at: 10.minutes.ago),
        create(:reminder_delivery_time, remindable: @org, next_delivery_at: Time.now),
        create(:reminder_delivery_time, remindable: @org, next_delivery_at: 9.minutes.from_now),
      ]

      not_upcoming = [
        create(:reminder_delivery_time, remindable: @org, next_delivery_at: 11.minutes.from_now),
        create(:reminder_delivery_time, remindable: @org, next_delivery_at: 1.year.from_now),
      ]

      assert_equal upcoming.sort_by(&:next_delivery_at), ReminderDeliveryTime.upcoming.sort_by(&:next_delivery_at)
    end
  end

  context "calculate_next_delivery_time" do
    test "returns next delivery time" do
      minus_12_tz = "International Date Line West" # -12 (makes for easy math)
      @reminder = create(:reminder, remindable: @org, days: ["Monday"], times: ["9:00 AM"], time_zone_name: minus_12_tz, user: @org.admin)
      @delivery_time = @reminder.delivery_times.first

      travel_to  Time.parse("2000-01-01T00:01Z") # It's a Saturday
      expected = Time.parse("2000-01-03T09:00Z") # January 3, 2000 at 9:00 PM UTC

      reminder = create(:reminder, remindable: @org, days: ["Monday"], times: ["9:00 AM"], time_zone_name: "UTC", user: @org.admin)
      delivery_time = reminder.delivery_times.first

      assert_equal expected, delivery_time.calculate_next_delivery_time
    end

    test "returns correct time for non-UTC on different day" do
      minus_12_tz = "International Date Line West" # -12 (makes for easy math)
      @reminder = create(:reminder, remindable: @org, days: ["Monday"], times: ["9:00 AM"], time_zone_name: minus_12_tz, user: @org.admin)
      @delivery_time = @reminder.delivery_times.first

      travel_to  Time.parse("2000-01-01T00:01Z") # It's a Saturday
      expected = Time.parse("2000-01-03T21:00Z") # January 3, 2000 at 9:00 PM UTC

      assert_equal expected, @delivery_time.calculate_next_delivery_time
    end

    test "returns correct time for non-UTC on same day" do
      minus_12_tz = "International Date Line West" # -12 (makes for easy math)
      @reminder = create(:reminder, remindable: @org, days: ["Monday"], times: ["9:00 AM"], time_zone_name: minus_12_tz, user: @org.admin)
      @delivery_time = @reminder.delivery_times.first

      travel_to  Time.parse("2000-01-03T20:59Z") # It's a Monday
      expected = Time.parse("2000-01-03T21:00Z") # January 3, 2000 at 9:00 PM UTC

      assert_equal expected, @delivery_time.calculate_next_delivery_time
    end

    test "returns next time when current minute is a delivery time" do
      minus_12_tz = "International Date Line West" # -12 (makes for easy math)
      @reminder = create(:reminder, remindable: @org, days: ["Monday"], times: ["9:00 AM"], time_zone_name: minus_12_tz, user: @org.admin)
      @delivery_time = @reminder.delivery_times.first

      travel_to  Time.parse("2000-01-03T21:00:01Z") # It's a Monday
      expected = Time.parse("2000-01-10T21:00Z") # January 10, 2000 at 9:00 PM UTC

      assert_equal expected, @delivery_time.calculate_next_delivery_time
    end

    test "returns next time when current second is a delivery time" do
      minus_12_tz = "International Date Line West" # -12 (makes for easy math)
      @reminder = create(:reminder, remindable: @org, days: ["Monday"], times: ["9:00 AM"], time_zone_name: minus_12_tz, user: @org.admin)
      @delivery_time = @reminder.delivery_times.first

      travel_to  Time.parse("2000-01-03T21:00Z") # It's a Monday
      expected = Time.parse("2000-01-10T21:00Z") # January 10, 2000 at 9:00 PM UTC

      assert_equal expected, @delivery_time.calculate_next_delivery_time
    end

    test "raises error when reminder is missing" do
      minus_12_tz = "International Date Line West" # -12 (makes for easy math)
      @reminder = create(:reminder, remindable: @org, days: ["Monday"], times: ["9:00 AM"], time_zone_name: minus_12_tz, user: @org.admin)
      @delivery_time = @reminder.delivery_times.first

      record = ReminderDeliveryTime.new(day: "Monday", time: "9:00 AM")

      assert_raises(RuntimeError) { record.calculate_next_delivery_time }
    end

    test "raises error when time invalid" do
      minus_12_tz = "International Date Line West" # -12 (makes for easy math)
      @reminder = create(:reminder, remindable: @org, days: ["Monday"], times: ["9:00 AM"], time_zone_name: minus_12_tz, user: @org.admin)
      @delivery_time = @reminder.delivery_times.first
      @delivery_time.time = nil

      assert_raises(RuntimeError) { @delivery_time.calculate_next_delivery_time }
    end
  end
end
