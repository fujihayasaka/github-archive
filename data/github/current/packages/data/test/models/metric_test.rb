# typed: true
# frozen_string_literal: true

require "test_helper"

class MetricTest < GitHub::TestCase
  def make_five_issues
    5.times { create :issue }
  end

  context "with data" do
    test "counts totals over period" do
      # Travel to a time that is not at the start of the day (00:00:00).
      # Tests will fail if happening at midnight, as items created right at
      # the start of the bucket are not counted.
      travel_to Time.zone.parse("2022-05-30 01:02:03") do
        make_five_issues
        assert_equal 5, Metric.build(:issues_created).reload!.total
      end
    end

    test "previous is for same number of buckets as current" do
      # Travelling to one week ago (the last full week) as it's likely the current week
      # will be icomplete and, thus, have less buckets
      timespan = MetricTimespan::Week.new(beginning: Time.zone.now - 1.week)
      metric = Metric.build(:issues_created, timespan: timespan).reload!

      assert_equal metric.count, metric.previous.reload!.count
    end

    test "total change shows total vs previous" do
      disable_feature_flag(:metric_query_kv)
      travel_to Time.zone.parse("2022-05-30 01:02:03") do
        make_five_issues
        assert_equal 5, Metric.build(:issues_created).reload!.total_change
      end
    end

    test "percent change shows change vs previous in terms of percent" do
      disable_feature_flag(:metric_query_kv)
      travel_to Time.zone.parse("2022-05-30 01:02:03") do
        make_five_issues
        assert_equal 500, Metric.build(:issues_created).reload!.percent_change
      end
    end
  end
end
