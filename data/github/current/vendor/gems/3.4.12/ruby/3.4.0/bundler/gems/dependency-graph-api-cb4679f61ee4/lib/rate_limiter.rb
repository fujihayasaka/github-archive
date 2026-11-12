# frozen_string_literal: true
# Public: Sliding window rate limiter to limit the number of times a block of
# code can be executed within a given time period.
#
# |----------------window----------------|
#
# |----step----|

#                                   t0
#                                   |
#                                   v
#
# [             bucket (current)         ]
#              [                bucket (future)          ]
#                           [                bucket (future)          ]
#
# The limiter is configured with a limit, a time window and number of buckets,
# and the step value is derived.
#
# options - The Hash options used to configure the limiter
#           :limit   - The Integer maximum number of calls that can happen with
#                      the window.
#           :window  - The Integer number of seconds in a time window.
#           :backoff - The Integer number of seconds to wait between tries.
#           :buckets - The Integer number of buckets. Essentially, the
#                      granularity of the limiter.
#           :clock   - A Time clock interface, mostly for testing.
#
# Examples
#
#   # Limit to 1000 calls in 1 minute
#   limiter = RateLimiter.new({
#     limit:   1000,
#     window:  60,
#     buckets: 10,
#     backoff: 10
#   })
#
#   limiter.limit { expensive_method }
#
class RateLimiter
  def initialize(options)
    @max          = options.fetch(:limit)
    @window       = options.fetch(:window)
    @bucket_count = options.fetch(:buckets)
    @backoff      = options.fetch(:backoff)
    @clock        = options.fetch(:clock, Time)
    @storage      = MemoryStorage.new(buckets: bucket_count)
  end

  def limit
    while wait?(now: clock.now.to_i)
      Instrument.increment("rate_limiter.limited")
      sleep(backoff)
    end

    yield.tap { storage.increment }
  end

  def step
    window / bucket_count
  end

  private

  attr_reader :backoff, :max, :clock, :window, :bucket_count, :storage

  def wait?(now:)
    current_bucket_id = get_bucket_id(now - window)

    bucket = storage.fetch_bucket(current_bucket_id) do
      bucket_count.times.map do |i|
        storage.add_bucket(current_bucket_id + i * step)
      end.first
    end

    bucket.count >= max
  end

  def get_bucket_id(time)
    time - (time % step)
  end

  class MemoryStorage
    def initialize(buckets:)
      @bucket_count = buckets
    end

    def fetch_bucket(bucket_id, &block)
      buckets.fetch(bucket_id, &block)
    end

    def add_bucket(bucket_id)
      (buckets[bucket_id] = Bucket.new(bucket_id)).tap { garbage_collect }
    end

    def increment
      buckets.values.each(&:increment)
    end

    def count(bucket_id:)
      buckets.fetch(bucket_id).count
    end

    private

    attr_reader :bucket_count

    def buckets
      @buckets ||= {}
    end

    def garbage_collect
      return unless buckets.count > bucket_count

      buckets.slice!(*buckets.keys.last(bucket_count))
    end

    class Bucket
      attr_reader :id, :count

      def initialize(id)
        @id    = id
        @count = 0
      end

      def increment
        @count += 1
      end
    end
  end
end
