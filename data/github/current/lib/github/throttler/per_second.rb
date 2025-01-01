# typed: true
# frozen_string_literal: true

module GitHub
  module Throttler
    # Public: GitHub::Throttler::PerSecond is a utility class for throttling how
    # many times a block is yielded per second. When PerSecondThrottler#run is
    # called the max times persecond it sleeps just long enough for the second
    # to be up and runs again.
    #
    # Example:
    #
    #   > throttler = GitHub::Throttler::PerSecond.new :per_second => 1
    #   => #<GitHub::Throttler::PerSecond:0x007fdba0c87ca0 @per_second=1, @counter=0, @start_time=2015-06-25 08:57:01 -0700>
    #
    #   > t = Time.now; 4.times {|n| throttler.run { puts n; puts Time.now - t } }
    #   0
    #   2.5e-05
    #   1
    #   1.00203
    #   2
    #   2.002386
    #   3
    #   3.003579
    #   => 4
    #
    # If the per_second value passed into the options hash in the initializer is
    # nil then Throttler#run yields the block with no throttling.
    class PerSecond

      def initialize(per_second: nil)
        unless per_second.nil? || (per_second.is_a?(Integer) && per_second >= 1)
          raise ArgumentError.new("\"#{per_second}\" is not a positive integer")
        end
        @per_second = per_second

        reset
      end

      # Public: Yield the block given, resetting counters if a second has passed
      # and pausing until the second is up if PerSecond#throttle? is true.
      #
      # &block - Block of code to run.
      def throttle(&block)
        reset if time_passed?

        if throttle?
          sleep_seconds = 1 - time_passed
          GitHub::Throttler.wait(sleep_seconds) if sleep_seconds > 0
          throttle(&block)
        else
          yield
          tick_counter
        end
      end

      # Counter for counting how many times Throttler#run has yielded
      # the given block. Resets to 0 when more than 1 second has passed
      #
      # Returns an Integer.
      attr_reader :counter

      # Value for how many times Throttler#run should yield the given
      # block per second.
      #
      # Returns an Integer or nil for noop.
      attr_reader :per_second

      # The start time for determining how much time has passed. Resets to current time when
      # more than 1 second has passed.
      #
      # Returns a Time.
      attr_reader :start_time

      private


      # Internal: The time that has passed in second.
      #
      # Returns a Float.
      def time_passed
        Time.now - start_time
      end

      # Internal: Has more than 1 second passed since Throttler#start_time?
      #
      # Returns a Boolean.
      def time_passed?
        time_passed > 1
      end

      # Internal: Is there a per_second value and has Throttler#counter reached
      # that per_second limit?
      #
      # Returns a Boolean.
      def throttle?
        per_second && counter >= per_second
      end

      # Internal: Reset Throttler#start_time to Time.now and
      # Throttler#counter to 0.
      def reset
        @start_time = Time.now
        @counter = 0
      end

      # Internal: Add 1 to Throttler#counter.
      def tick_counter
        @counter += 1
      end
    end
  end
end
