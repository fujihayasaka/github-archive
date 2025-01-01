# typed: true
# frozen_string_literal: true

require "test_helper"

module Newsies
  class MobilePushNotificationScheduleTest < GitHub::TestCase
    setup do
      @user = create :user
      create :profile, user: @user, mobile_time_zone_name: "America/Chicago"
    end

    context "validations" do
      test "is not valid for invalid days" do
        schedule = build :mobile_push_notification_schedule, day: nil
        refute schedule.valid?
        assert_equal "Day can't be blank", schedule.errors.full_messages[0]

        assert_raises ArgumentError, "'yesterday' is not a valid day" do
          build :mobile_push_notification_schedule, day: "yesterday"
        end
      end

      test "is not valid for a user with multiple schedules for the same day" do
        schedule = create :mobile_push_notification_schedule, day: "monday"
        assert schedule.persisted?

        other_schedule = build :mobile_push_notification_schedule, day: "monday", user: schedule.user
        refute other_schedule.valid?
        assert_equal "Day has already been taken", other_schedule.errors.full_messages[0]
      end

      test "is not valid for an invalid start_time format" do
        schedule = build :mobile_push_notification_schedule, start_time: "0:"
        refute schedule.valid?
        assert_equal "Start time is invalid", schedule.errors.full_messages[0]

        schedule = build :mobile_push_notification_schedule, start_time: "60:69"
        refute schedule.valid?
        assert_equal "Start time is invalid", schedule.errors.full_messages[0]
      end

      test "is not valid for an invalid end_time format" do
        schedule = build :mobile_push_notification_schedule, end_time: "0:"
        refute schedule.valid?
        assert_equal "End time is invalid", schedule.errors.full_messages[0]

        schedule = build :mobile_push_notification_schedule, end_time: "60:69"
        refute schedule.valid?
        assert_equal "End time is invalid", schedule.errors.full_messages[0]
      end

      test "is valid" do
        schedule = build :mobile_push_notification_schedule, day: "monday", start_time: "08:00", end_time: "23:59"
        assert schedule.valid?
      end
    end

    context ".deliver_to_user?" do
      test "returns false if user is blank" do
        refute Newsies::MobilePushNotificationSchedule.deliver_to_user?(nil)
      end

      context "with scheduled notifications enabled" do
        test "returns true if the user has no schedules" do
          Notifyd::MobilePushSettingsStore.any_instance.stubs(:get).returns(Notifyd::MobilePushSettings.default)
          Notifyd::MobilePushSettingsStore.any_instance.stubs(:save).returns(true)
          create(:mobile_push_notification_setting, user: @user, scheduled_notifications: true)

          assert_equal true, Newsies::MobilePushNotificationSchedule.deliver_to_user?(@user)
        end

        test "returns false if start_time and end_time is nil" do
          Notifyd::MobilePushSettingsStore.any_instance.stubs(:get).returns(Notifyd::MobilePushSettings.default)
          Notifyd::MobilePushSettingsStore.any_instance.stubs(:save).returns(true)
          create(:mobile_push_notification_setting, user: @user, scheduled_notifications: true)
          Timecop.freeze("2020-06-9 00:00:00") do
            Time.zone = "America/Chicago"

            create(:mobile_push_notification_schedule,
              day: "thursday",
              end_time: nil,
              start_time: nil,
              user: @user,
            )

            refute Newsies::MobilePushNotificationSchedule.deliver_to_user?(@user)
          end
        end

        test "returns false if the current time falls outside the users available schedules" do
          Notifyd::MobilePushSettingsStore.any_instance.stubs(:get).returns(Notifyd::MobilePushSettings.default)
          Notifyd::MobilePushSettingsStore.any_instance.stubs(:save).returns(true)
          create(:mobile_push_notification_setting, user: @user, scheduled_notifications: true)
          Timecop.freeze("2020-06-9 00:00:00") do
            Time.zone = "America/Chicago"

            create(:mobile_push_notification_schedule,
              day: "thursday",
              start_time: "8:00",
              end_time: "17:00",
              user: @user,
            )

            refute Newsies::MobilePushNotificationSchedule.deliver_to_user?(@user)
          end
        end

        test "returns true if the current time falls within the users available schedules" do
          Notifyd::MobilePushSettingsStore.any_instance.stubs(:get).returns(Notifyd::MobilePushSettings.default)
          Notifyd::MobilePushSettingsStore.any_instance.stubs(:save).returns(true)
          create(:mobile_push_notification_setting, user: @user, scheduled_notifications: true)
          Timecop.freeze("2020-06-10 15:00:00") do # Wednesday June 10th, 2020
            Time.zone = "America/Chicago"

            create(:mobile_push_notification_schedule,
              day: "wednesday",
              start_time: "8:00",
              end_time: "17:00",
              user: @user,
            )

            assert_equal true, Newsies::MobilePushNotificationSchedule.deliver_to_user?(@user)
          end
        end
      end

      context "with scheduled notifications disabled" do
        test "returns true if the user has disabled scheduled notifications" do
          Notifyd::MobilePushSettingsStore.any_instance.stubs(:get).returns(Notifyd::MobilePushSettings.default)
          Notifyd::MobilePushSettingsStore.any_instance.stubs(:save).returns(true)
          create(:mobile_push_notification_setting, user: @user, scheduled_notifications: false)
          Timecop.freeze("2020-06-10 01:00:00") do # Wednesday June 10th, 2020
            Time.zone = "America/Chicago"

            create(:mobile_push_notification_schedule,
              day: "wednesday",
              start_time: "8:00",
              end_time: "17:00",
              user: @user,
            )

            assert Newsies::MobilePushNotificationSchedule.deliver_to_user?(@user)
          end
        end
      end
    end
  end
end
