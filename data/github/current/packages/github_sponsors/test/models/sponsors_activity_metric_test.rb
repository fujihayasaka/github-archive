# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsActivityMetricTest < GitHub::TestCase
  context "most_recent scope" do
    test "returns most recent metric relative to the specified day" do
      now = Time.now

      Timecop.freeze(now) do
        metric = create(:sponsors_activity_metric, recorded_on: 3.days.ago)

        most_recent = SponsorsActivityMetric.most_recent(as_of: 2.days.ago)
        assert_equal [metric], most_recent
      end
    end

    test "returns empty if no previous metrics exist" do
      now = Time.now

      Timecop.freeze(now) do
        metric = create(:sponsors_activity_metric, recorded_on: 2.days.ago)

        most_recent = SponsorsActivityMetric.most_recent(as_of: 3.days.ago)
        assert_predicate most_recent, :empty?
      end
    end
  end

  context "on scope" do
    test "returns metric for the specified day" do
      now = Time.now

      Timecop.freeze(now) do
        metric = create(:sponsors_activity_metric, recorded_on: 2.days.ago)

        day_metric = SponsorsActivityMetric.on(2.days.ago)
        assert_equal [metric], day_metric
      end
    end

    test "returns empty if no metrics recorded that day" do
      now = Time.now

      Timecop.freeze(now) do
        metric = create(:sponsors_activity_metric, recorded_on: 3.days.ago)

        day_metric = SponsorsActivityMetric.on(2.days.ago)
        assert_predicate day_metric, :empty?
      end
    end
  end
end
