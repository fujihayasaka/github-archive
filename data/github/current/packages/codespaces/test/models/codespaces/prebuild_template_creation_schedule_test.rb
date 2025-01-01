# typed: true
# frozen_string_literal: true

require "test_helper"

class CodespacePrebuildTemplateCreationScheduleTests < GitHub::TestCase
  fixtures do
    @simple_repo = create(:repository, owner: create(:organization), from_example: :refs_test)
  end

  context "#delivery_day" do
    test "is converted to an enum" do
      create(:codespace_prebuild_template_creation_schedule, delivery_time: "5:00 AM", delivery_day: "Monday")

      refute_nil Codespaces::PrebuildTemplateCreationSchedule.find_by(
        delivery_time: "5:00 AM",
        delivery_day: Codespaces::PrebuildTemplateCreationSchedule::delivery_days["Monday"])
    end

    test "must exist" do

      assert_raises_with_message ActiveRecord::RecordInvalid, "Validation failed: Delivery day can't be blank" do
        create(:codespace_prebuild_template_creation_schedule, delivery_day: nil)
      end
    end
  end

  context "#delivery_time" do
    test "is converted to an enum" do
      create(:codespace_prebuild_template_creation_schedule, delivery_time: "5:00 AM", delivery_day: "Monday")

      refute_nil Codespaces::PrebuildTemplateCreationSchedule.find_by(
        delivery_time: Codespaces::PrebuildTemplateCreationSchedule::delivery_times["5:00 AM"],
        delivery_day: "Monday")
    end

    test "must exist" do
      assert_raises_with_message ActiveRecord::RecordInvalid, "Validation failed: Delivery time can't be blank" do
        create(:codespace_prebuild_template_creation_schedule, delivery_time: nil)
      end
    end
  end

  context "#next_delivery_at" do
    test "is calculated on create" do
      date_time = Time.new
      current_dt = date_time.inspect

      create(:codespace_prebuild_template_creation_schedule, delivery_time: "5:00 AM", time_zone_name: "America/New_York")
      schedule = Codespaces::PrebuildTemplateCreationSchedule.find_by(delivery_time: "5:00 AM")
      refute_nil schedule
      refute_nil T.must(schedule).next_delivery_at

      assert_equal 5, T.must(schedule).next_delivery_at.in_time_zone(ActiveSupport::TimeZone["America/New_York"]).hour
    end
  end

  context "#time_zone_name" do
    test "is saved on create" do
      create(:codespace_prebuild_template_creation_schedule,
        delivery_time: "5:00 AM",
        delivery_day: "Monday",
        time_zone_name: "America/New_York")

      refute_nil Codespaces::PrebuildTemplateCreationSchedule.find_by(
        delivery_time: "5:00 AM",
        delivery_day: Codespaces::PrebuildTemplateCreationSchedule::delivery_days["Monday"],
        time_zone_name: "America/New_York")
    end

    test "must exist" do

      assert_raises_with_message ActiveRecord::RecordInvalid, "Validation failed: Time zone name can't be blank" do
        create(:codespace_prebuild_template_creation_schedule, time_zone_name: nil)
      end
    end

  end

  context "#upcoming" do
    test "finds records to be delivered in the next 10 minutes" do
      prebuild_template_schedule1 = create(:codespace_prebuild_template_creation_schedule, next_delivery_at: 19.minutes.from_now(Time.now.utc))
      prebuild_template_schedule1 = create(:codespace_prebuild_template_creation_schedule, next_delivery_at: 9.minutes.from_now(Time.now.utc))
      prebuild_template_schedule2 = create(:codespace_prebuild_template_creation_schedule, next_delivery_at: 5.minutes.from_now(Time.now.utc))

      schedules = Codespaces::PrebuildTemplateCreationSchedule.upcoming
      refute_nil schedules
      assert_equal schedules.count, 2
    end

    test "finds records to be delivered that are past due" do
      prebuild_template_schedule1 = create(:codespace_prebuild_template_creation_schedule, next_delivery_at: 19.minutes.from_now(Time.now.utc))
      prebuild_template_schedule1 = create(:codespace_prebuild_template_creation_schedule, next_delivery_at: -9.minutes.from_now(Time.now.utc))
      prebuild_template_schedule2 = create(:codespace_prebuild_template_creation_schedule, next_delivery_at: -5.minutes.from_now(Time.now.utc))

      schedules = Codespaces::PrebuildTemplateCreationSchedule.upcoming
      refute_nil schedules
      assert_equal schedules.count, 2
    end
  end
end
