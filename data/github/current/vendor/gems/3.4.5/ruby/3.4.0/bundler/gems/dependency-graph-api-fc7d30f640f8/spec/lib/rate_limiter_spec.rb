require "spec_helper"
require "rate_limiter"
require "active_support"
require "active_support/core_ext"

describe RateLimiter do
  it "limits calls" do
    clock = TestClock.new(Time.new(2016, 10, 10, 0, 0, 0))
    count = 0

    limiter = described_class.new({
      limit:   10,
      window:  1.minute,
      backoff: 2.seconds,
      buckets: 10,
      clock:   clock,
    })

    expect(limiter.step).to eq 6.seconds

    5.times { limiter.limit { count += 1 } }
    expect(count).to eq 5

    # Blast into the future to t0 + 15 seconds.
    clock.now = Time.new(2016, 10, 10, 0, 0, 15)

    # Increment up to the limit.
    5.times { limiter.limit { count += 1 } }
    expect(count).to eq 10

    # Attempt to exceed the limit.
    thread = Thread.new { limiter.limit { count += 1 } }

    # Give the thread a chance to execute.
    sleep 1
    # Execution should be blocked until we get to t0 + 61.
    expect(count).to eq(10)

    # Blast into the future to t0 + 61 seconds to get outside the first window.
    clock.now = Time.new(2016, 10, 10, 0, 1, 1)

    # We should be now be able to proceed after backoff.
    thread.join
    expect(count).to eq(11)
  end

  class TestClock
    attr_accessor :now

    def initialize(now)
      @now = now
    end
  end
end
