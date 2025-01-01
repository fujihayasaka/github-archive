# typed: true
# frozen_string_literal: true

module GitHub
  module BootMetrics
    extend self

    attr_accessor :initial_boot_time

    @states = {}

    # Called at each phase in the boot process to record the current state
    def record_state(state, additional_metrics = {})
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @states[state] ||= {
        "time" => now - initial_boot_time,
        "memory_rss" => GitHub::Memory.memrss,
        "gc.total_allocations" => GC.stat(:total_allocated_objects),
        "gc.heap_live_slots" => GC.stat(:heap_live_slots),
        "gc.heap_sorted_length" => GC.stat(:heap_sorted_length),
      }.merge(additional_metrics)
    end

    # Actually report our data to datadog.
    # This should be called after the very last call to record_state
    def send_to_datadog
      @states.each do |state, metrics|
        metrics.each do |metric, value|
          GitHub.dogstats.distribution("boot.#{state}.#{metric}", value)
        end
      end
    end
  end
end
