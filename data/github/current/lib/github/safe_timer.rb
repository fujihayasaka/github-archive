# typed: true
# frozen_string_literal: true

# GitHub::Timer implements a timeout that raises an exception when the timeout
# has expired. This can be dangerous as it could raise in the middle of code
# that is not designed to be interrupted and end up corrupting state.
#
# GitHub::SafeTimer is a timeout that does not raise any exceptions. Instead,
# it's the responsibility of calling code to check that the timeout has not
# yet expired.
#
# Usage example:
#
#   GitHub::SafeTimer.timeout(1) do |timer|
#     while timer.run? && do_stuff?
#       do_stuff!
#     end
#   end
#
# This is less precise that GitHub::Timer (as it depends on how long do_stuff!
# runs for) - but in some cases the imprecision might not be an issue.
#
# Use thoughtfully.
#
module GitHub
  class SafeTimer
    def self.timeout(seconds)
      yield new(seconds)
    end

    def initialize(seconds)
      @expires_at = current_time + seconds
    end

    def run?
      !expired?
    end

    def expired?
      current_time >= @expires_at
    end

    private

    def current_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
