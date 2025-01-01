# typed: true
# frozen_string_literal: true

require "test_helper"

class MergeQueue::TimeToMergeEstimatorTest < GitHub::TestCase
  fixtures do
    @queue = create(:merge_queue)
  end

  setup do
    travel_to(Time.parse("2020-09-01T12:00:00Z"))
  end

  context "#estimate" do
    test "calculates the linear trend of time to merge from the past week" do
      # Excluded, too old
      create(:merge_queue_entry_stat,
        queue: @queue,
        enqueued_at: 8.days.ago,
        enqueued_in_position: 10,
        merged_at: 8.days.ago + 10.minutes,
      )

      # Included, first in line, waited 10 minutes
      create(:merge_queue_entry_stat,
        queue: @queue,
        enqueued_at: 6.days.ago,
        enqueued_in_position: 1,
        merged_at: 6.days.ago + 10.minutes,
      )

      # Excluded, not merged
      create(:merge_queue_entry_stat,
        queue: @queue,
        enqueued_at: 5.days.ago,
        enqueued_in_position: 2,
        merged_at: nil,
      )

      # Included, second in line, waited 30 minutes
      create(:merge_queue_entry_stat,
        queue: @queue,
        enqueued_at: 4.days.ago,
        enqueued_in_position: 2,
        merged_at: 4.days.ago + 30.minutes,
      )

      # Included, third in line, waited 40 minutes
      create(:merge_queue_entry_stat,
        queue: @queue,
        enqueued_at: 1.day.ago,
        enqueued_in_position: 3,
        merged_at: 1.day.ago + 40.minutes,
      )

      estimator = MergeQueue::TimeToMergeEstimator.new(queue: @queue)

      assert_equal duration(m: 11, s: 40), estimator.estimate(position: 1)
      assert_equal duration(m: 26, s: 40), estimator.estimate(position: 2)
      assert_equal duration(m: 41, s: 40), estimator.estimate(position: 3)
      assert_equal duration(m: 56, s: 40), estimator.estimate(position: 4)
      assert_equal duration(h: 2, m: 26, s: 40), estimator.estimate(position: 10)
      assert_equal duration(h: 4, m: 56, s: 40), estimator.estimate(position: 20)
    end

    test "caches the formula for performance" do
      with_cache_enabled do
        create(:merge_queue_entry_stat,
          queue: @queue,
          enqueued_at: 6.days.ago,
          enqueued_in_position: 1,
          merged_at: 6.days.ago + 10.minutes,
        )

        create(:merge_queue_entry_stat,
          queue: @queue,
          enqueued_at: 4.days.ago,
          enqueued_in_position: 2,
          merged_at: 4.days.ago + 30.minutes,
        )

        create(:merge_queue_entry_stat,
          queue: @queue,
          enqueued_at: 1.day.ago,
          enqueued_in_position: 3,
          merged_at: 1.day.ago + 40.minutes,
        )

        estimator = MergeQueue::TimeToMergeEstimator.new(queue: @queue)
        assert_equal duration(m: 56, s: 40), estimator.estimate(position: 4)

        # Will be included when the cache expires
        create(:merge_queue_entry_stat,
          queue: @queue,
          enqueued_at: 50.minutes.ago,
          enqueued_in_position: 4,
          merged_at: Time.current,
        )

        # Formula is cached, estimate is unchanged
        new_estimator = MergeQueue::TimeToMergeEstimator.new(queue: @queue)
        assert_equal duration(m: 56, s: 40), new_estimator.estimate(position: 4)

        reset_cache

        # Cache expires, estimate changes
        assert_equal duration(m: 52, s: 0), new_estimator.estimate(position: 4)
      end
    end

    test "never estimates a negative time to merge" do
      # Based on linear regression alone, the datapoints below would predict a
      # negative wait time, which is unhelpful!
      create(:merge_queue_entry_stat,
        queue: @queue,
        enqueued_at: 3.days.ago,
        enqueued_in_position: 1,
        merged_at: 3.days.ago + 0.minutes,
      )

      create(:merge_queue_entry_stat,
        queue: @queue,
        enqueued_at: 2.days.ago,
        enqueued_in_position: 2,
        merged_at: 2.days.ago + 10.minutes,
      )

      create(:merge_queue_entry_stat,
        queue: @queue,
        enqueued_at: 1.day.ago,
        enqueued_in_position: 3,
        merged_at: 1.day.ago + 30.minutes,
      )

      estimator = MergeQueue::TimeToMergeEstimator.new(queue: @queue)

      assert_equal 0, estimator.estimate(position: 1)
    end

    test "returns nil if there isn't enough data" do
      # At least two datapoints are required.
      create(:merge_queue_entry_stat,
        queue: @queue,
        enqueued_at: 1.day.ago,
        enqueued_in_position: 1,
        merged_at: 1.day.ago + 10.minutes,
      )

      estimator = MergeQueue::TimeToMergeEstimator.new(queue: @queue)

      assert_nil estimator.estimate(position: 1)
    end

    test "returns nil if a linear trend can't be determined" do
      # All datapoints have the same X (initial position) value.
      create(:merge_queue_entry_stat,
        queue: @queue,
        enqueued_at: 2.days.ago,
        enqueued_in_position: 1,
        merged_at: 2.days.ago + 10.minutes,
      )

      create(:merge_queue_entry_stat,
        queue: @queue,
        enqueued_at: 1.day.ago,
        enqueued_in_position: 1,
        merged_at: 1.day.ago + 20.minutes,
      )

      estimator = MergeQueue::TimeToMergeEstimator.new(queue: @queue)

      assert_nil estimator.estimate(position: 1)
    end

    test "calculates based on a configurable window of time" do
      create(:merge_queue_entry_stat,
        queue: @queue,
        enqueued_at: 3.weeks.ago,
        enqueued_in_position: 1,
        merged_at: 3.weeks.ago + 10.minutes,
      )

      create(:merge_queue_entry_stat,
        queue: @queue,
        enqueued_at: 2.days.ago,
        enqueued_in_position: 2,
        merged_at: 2.days.ago + 30.minutes,
      )

      create(:merge_queue_entry_stat,
        queue: @queue,
        enqueued_at: 1.day.ago,
        enqueued_in_position: 3,
        merged_at: 1.day.ago + 40.minutes,
      )

      week_estimator = MergeQueue::TimeToMergeEstimator.new(queue: @queue)
      month_estimator = MergeQueue::TimeToMergeEstimator.new(queue: @queue, window: 1.month)

      assert_equal duration(h: 1, m: 50), week_estimator.estimate(position: 10)
      assert_equal duration(h: 2, m: 26, s: 40), month_estimator.estimate(position: 10)
    end
  end

  # Used to increase clarity in tests and provide better failure messages by
  # comparing integers rather than Rails' durations.
  def duration(h: 0, m: 0, s: 0)
    (h.hours + m.minutes + s.seconds).to_i
  end
end
