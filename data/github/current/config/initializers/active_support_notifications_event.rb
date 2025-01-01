# typed: true
# frozen_string_literal: true

# This monkey patch changes the implementation of the now_cpu method to return 0.0 instead
# of taking the actual CPU timer with `Process.clock_gettime`. This change is here to avoid
# the overhead of the system call that `Process.clock_gettime` makes when using any of the
# CPU clocks. As a consequence, the `cpu_time` and `idle_time` methods on the `Event` class
# will not be accurate.

if ENV["ACTIVE_SUPPORT_SKIP_CPU_TIME"] == "1"
  class ActiveSupport::Notifications::Event
    def now_cpu
      0.0
    end
  end
end
