# typed: strict
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

module SecurityOverviewAnalytics
  class CalendarPopulationJobTest < GitHub::TestCase
    include JobTestHelper

    setup do
      GitHub.flipper[:security_overview_analytics_calendar_population_job_enabled].enable
    end

    context "testing populate_calendar" do
      test "creates one batch dates from 2010" do
        Timecop.freeze(Time.utc(2020, 1, 1)) do
          assert_difference("SecurityOverviewAnalytics::Date.count", 1000) do
            SecurityOverviewAnalytics::CalendarPopulationJob.perform_now
          end
        end
        assert_equal Time.utc(2010, 1, 1), SecurityOverviewAnalytics::Date.minimum(:date_value)
        assert_equal Time.utc(2010, 1, 1) + 999.days, SecurityOverviewAnalytics::Date.maximum(:date_value)
      end

      test "starts data population from the current max date stored" do
        SecurityOverviewAnalytics::Date.create(id: 20150101, date_value: Time.utc(2015, 1, 1))
        Timecop.freeze(Time.utc(2015, 1, 10)) do
          # Creates one year plus 9 extra days
          assert_difference("SecurityOverviewAnalytics::Date.count", 365 + 9) do
            SecurityOverviewAnalytics::CalendarPopulationJob.perform_now
          end
        end
        assert_equal Time.utc(2015, 1, 1), SecurityOverviewAnalytics::Date.minimum(:date_value)
        assert_equal Time.utc(2016, 1, 10), SecurityOverviewAnalytics::Date.maximum(:date_value)
      end

      test "does not touch dates on rerun" do
        Timecop.freeze(Time.utc(2020, 1, 1)) do

          # Full calendar from 2010 till 2020 fits in 4 batches of 1k date rows
          assert_performed_jobs 4 do
            SecurityOverviewAnalytics::CalendarPopulationJob.perform_now
          end

          assert_no_difference("SecurityOverviewAnalytics::Date.count") do
            SecurityOverviewAnalytics::CalendarPopulationJob.perform_now
          end
        end
      end

      test "adds date records if time passed and new dates have to be added" do
        Timecop.freeze(Time.utc(2020, 1, 1)) do
          # Full calendar from 2010 till 2020 fits in 4 batches of 1k date rows
          assert_performed_jobs 4 do
            SecurityOverviewAnalytics::CalendarPopulationJob.perform_now
          end

          assert_difference("SecurityOverviewAnalytics::Date.count", 1) do
            Timecop.freeze(Time.utc(2020, 1, 2)) do
              SecurityOverviewAnalytics::CalendarPopulationJob.perform_now
            end
          end
        end
        assert_equal Time.utc(2010, 1, 1), SecurityOverviewAnalytics::Date.minimum(:date_value)
        # Max value is a year from current/frozen date
        assert_equal Time.utc(2021, 1, 2), SecurityOverviewAnalytics::Date.maximum(:date_value)
      end
    end
  end
end
