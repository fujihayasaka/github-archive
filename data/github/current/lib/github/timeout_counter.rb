# typed: false
# frozen_string_literal: true

module GitHub
  # Helper class that takes a timeout in seconds on initialization.
  # The #update function executes blocks and reduces the time required
  # for these blocks from the initial timeout.
  #
  class TimeoutCounter

    # Remaining time in seconds
    attr_reader :remaining

    def initialize(timeout_in_sec = 8)
      @remaining = timeout_in_sec
    end

    def min_remaining(other)
      other = other.remaining if other.is_a? self.class
      [remaining, other].compact.min
    end

    def set_min_remaining(other)
      @remaining = min_remaining(other)
    end

    def update(&block)
      start = Time.now
      block.call
    ensure
      elapsed = Time.now - start
      @remaining = remaining - elapsed
      @remaining = 0 if remaining < 0
    end

    def timeout?
      remaining <= 0
    end
  end
end
