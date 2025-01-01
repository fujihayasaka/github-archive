# typed: true
# frozen_string_literal: true

require "test_helper"

class ChecksJobUtilityTest < GitHub::TestCase
  setup do
    @checks_job_utility_module = Object.new
    @checks_job_utility_module.extend ChecksJobUtility
  end

  context "weekend peak traffic times" do
    test "Sunday Midnight" do
      time = Time.parse("2000-01-02T00:00Z") # Sunday
      Time.stubs(:now).returns(time)
      refute @checks_job_utility_module.peak_traffic_time?
    end

    test "Sunday 8 AM UTC" do
      time = Time.parse("2000-01-02T08:00Z") # Sunday
      Time.stubs(:now).returns(time)
      refute @checks_job_utility_module.peak_traffic_time?
    end

    test "Sunday 6 PM UTC" do
      time = Time.parse("2000-01-02T18:00Z") # Sunday
      Time.stubs(:now).returns(time)
      refute @checks_job_utility_module.peak_traffic_time?
    end

    test "Sunday 7 PM UTC" do
      time = Time.parse("2000-01-02T19:00Z") # Sunday
      Time.stubs(:now).returns(time)
      refute @checks_job_utility_module.peak_traffic_time?
    end

    test "Saturday" do
      time = Time.parse("2000-01-01T00:00Z") # Saturday
      Time.stubs(:now).returns(time)
      refute @checks_job_utility_module.peak_traffic_time?
    end

    test "Saturday with weekend_deletion_window" do
      time = Time.parse("2000-01-08T00:00Z") # Saturday
      Time.stubs(:now).returns(time)
      assert @checks_job_utility_module.weekend_deletion_window?
    end

    test "Sunday with weekend_deletion_window" do
      time = Time.parse("2000-01-09T00:00Z") # Sunday
      Time.stubs(:now).returns(time)
      assert @checks_job_utility_module.weekend_deletion_window?
    end

    test "Monday with weekend_deletion_window" do
      time = Time.parse("2000-01-10T00:00Z") # Monday
      Time.stubs(:now).returns(time)
      refute @checks_job_utility_module.weekend_deletion_window?
    end

    test "Friday with weekend_deletion_window" do
      time = Time.parse("2000-01-07T00:00Z") # Friday
      Time.stubs(:now).returns(time)
      refute @checks_job_utility_module.weekend_deletion_window?
    end
  end

  context "weekday peak traffic times" do
    test "Monday Midnight" do
      time = Time.parse("2000-01-03T00:00Z") # Monday
      Time.stubs(:now).returns(time)
      refute @checks_job_utility_module.peak_traffic_time?
    end

    test "Monday 6:59 AM UTC" do
      time = Time.parse("2000-01-03T06:59Z") # Monday
      Time.stubs(:now).returns(time)
      refute @checks_job_utility_module.peak_traffic_time?
    end

    test "Monday 7 AM UTC" do
      time = Time.parse("2000-01-03T07:00Z") # Monday
      Time.stubs(:now).returns(time)
      assert @checks_job_utility_module.peak_traffic_time?
    end

    test "Monday 6:59 PM UTC" do
      time = Time.parse("2000-01-03T18:59Z") # Monday
      Time.stubs(:now).returns(time)
      assert @checks_job_utility_module.peak_traffic_time?
    end

    test "Monday 7 PM UTC" do
      time = Time.parse("2000-01-03T19:00Z") # Monday
      Time.stubs(:now).returns(time)
      refute @checks_job_utility_module.peak_traffic_time?
    end

    test "Tuesday midnight" do
      time = Time.parse("2000-01-04T00:00Z") # Tuesday
      Time.stubs(:now).returns(time)
      refute @checks_job_utility_module.peak_traffic_time?
    end

    test "Wednesday 10 AM UTC" do
      time = Time.parse("2000-01-05T10:00Z") # Wednesday
      Time.stubs(:now).returns(time)
      assert @checks_job_utility_module.peak_traffic_time?
    end

    test "Thursday 4 PM UTC" do
      time = Time.parse("2000-01-06T16:00Z") # Thursday
      Time.stubs(:now).returns(time)
      assert @checks_job_utility_module.peak_traffic_time?
    end

    test "Thursday 8 PM UTC" do
      time = Time.parse("2000-01-06T20:00Z") # Thursday
      Time.stubs(:now).returns(time)
      refute @checks_job_utility_module.peak_traffic_time?
    end

    test "Friday 6 AM UTC" do
      time = Time.parse("2000-01-07T06:00Z") # Friday
      Time.stubs(:now).returns(time)
      refute @checks_job_utility_module.peak_traffic_time?
    end

    test "Friday 1 PM UTC" do
      time = Time.parse("2000-01-07T13:00Z") # Friday
      Time.stubs(:now).returns(time)
      assert @checks_job_utility_module.peak_traffic_time?
    end
  end

  context "ramp up traffic times" do
    test "Saturdays do not have a ramp up time" do
      time = Time.parse("2000-01-01T19:05Z") # Saturday
      Time.stubs(:now).returns(time)
      refute @checks_job_utility_module.ramp_up_retention_time?
    end

    test "Sundays do not have a ramp up time" do
      time = Time.parse("2000-01-02T19:05Z") # Sunday
      Time.stubs(:now).returns(time)
      refute @checks_job_utility_module.ramp_up_retention_time?
    end

    test "Mondays do have a ramp up time" do
      time = Time.parse("2000-01-03T19:05Z") # Monday
      Time.stubs(:now).returns(time)
      assert @checks_job_utility_module.ramp_up_retention_time?
    end

    test "29 minutes past the hour is a ramp up time" do
      time = Time.parse("2000-01-03T19:29Z") # Monday
      Time.stubs(:now).returns(time)
      assert @checks_job_utility_module.ramp_up_retention_time?
    end

    test "31 minutes past the hour is not ramp up" do
      time = Time.parse("2000-01-03T19:31Z") # Monday
      Time.stubs(:now).returns(time)
      refute @checks_job_utility_module.ramp_up_retention_time?
    end

    test "before the hour is not a ramp up time" do
      time = Time.parse("2000-01-03T18:57Z") # Monday
      Time.stubs(:now).returns(time)
      refute @checks_job_utility_module.ramp_up_retention_time?
    end
  end

  context "grouping utility" do
    test "group by repository_id" do
      # In the tuple input the first id is expected to be the repository_id while the second on is the object database ID#
      # This is some output from doing pluck(:repository_id, :id)
      sample_data = [[1, 1], [2, 2], [1, 3], [1, 4], [3, 5], [2, 6], [3, 7], [1, 8], [2, 9], [3, 10]]
      expected_output = {
        1 => [1, 3, 4, 8],
        2 => [2, 6, 9],
        3 => [5, 7, 10]
      }

      assert_equal expected_output, @checks_job_utility_module.group_by_repository_id(sample_data)
    end
  end
end
