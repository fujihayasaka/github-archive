# typed: true
# frozen_string_literal: true

# Internal: Estimate the time to merge in a merge queue by finding the linear trend
# of historical times to merge vs. initial position in the given queue, and using
# that trend to estimate time to merge for any given position in the queue.
#
# The linear trend formula is cached to prevent frequent querying for data that
# changes slowly.
#
# Examples
#
#   estimator = MergeQueue::TimeToMergeEstimator.new(queue: queue)
#   estimator.estimate(position: 2) # Calculates trend
#   # => 2520
#   estimator.estimate(position: 3) # Uses cached trend
#   # => 3690
class MergeQueue::TimeToMergeEstimator
  # Internal: How far to look back (by default) for historical data.
  WINDOW = 1.week

  def initialize(queue:, window: WINDOW)
    @queue = queue
    @window = window
  end

  attr_reader :queue, :window

  def estimate(position:)
    return unless position

    slope, intercept = slope_and_intercept
    return unless slope && intercept

    [(slope * position) + intercept, 0].max
  end

  private

  def slope_and_intercept
    GitHub.cache.fetch(cache_key, ttl: cache_expiration) do
      calculate_slope_and_intercept
    end
  end

  def cache_key
    "merge_queue:time_to_merge:#{queue.id}:#{window}"
  end

  def cache_expiration
    window / 100
  end

  def calculate_slope_and_intercept
    datapoints = fetch_datapoints
    count = datapoints.count
    return nil if count < 2 # Not enough data
    sum_of_product = sum_of_x = sum_of_y = sum_of_x_squared = 0

    # One iteration over datapoints rather than several via reduce or inject.
    datapoints.each do |x, y|
      sum_of_product += (x * y)
      sum_of_x += x
      sum_of_y += y
      sum_of_x_squared += (x**2)
    end

    slope = ((count * sum_of_product) - (sum_of_x * sum_of_y)) /
      ((count * sum_of_x_squared) - (sum_of_x**2))
    intercept = (sum_of_y - (slope * sum_of_x)) / count

    [slope, intercept]
  rescue ZeroDivisionError
    nil
  end

  def fetch_datapoints
    queue.
      entry_stats.
      where("merged_at >= ?", window.ago).
      pluck(
        :enqueued_in_position,
        Arel.sql("TIMESTAMPDIFF(SECOND, enqueued_at, merged_at)"),
      )
  end
end
