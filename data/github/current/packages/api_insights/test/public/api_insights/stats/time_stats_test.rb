# typed: true
# frozen_string_literal: true

require "test_helper"

module ApiInsights::Stats
  class TimeStatsTest < GitHub::TestCase
    test "initialization adds additional summary key fields" do
      timestamp_increment = "1h"
      time_stats = TestableTimeStats.new timestamp_increment
      refute_nil time_stats.query.timestamp_increment_summary_key
      assert_equal timestamp_increment, time_stats.query.timestamp_increment_summary_key.timestamp_increment
    end

    test "should validate sort field correctly" do
      valid_sort_field = Queries::SortField::Timestamp
      invalid_sort_field = Queries::SortField::SubjectName

      time_stats = TestableTimeStats.new "1h"

      assert time_stats.send(:valid_sort_field?, valid_sort_field)
      assert_not time_stats.send(:valid_sort_field?, invalid_sort_field)
    end
  end

  class TestableTimeStats < TimeStats
    def initialize(timestamp_increment)
      now = Time.now.utc
      super 1, now - 1.day, now, timestamp_increment
    end

    def query
      super
    end
  end
end
