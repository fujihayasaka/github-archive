# typed: true
# frozen_string_literal: true

module GitHub
  module DataCollector
    class GCStatsCollector < GitHub::DataCollector::Collector
      set_callback :reset, :after do |collector|
        collector.gc_count = GC.count
        collector.gc_time = GC.total_time
        collector.minor_gc_count = GC.stat(:minor_gc_count)
        collector.major_gc_count = GC.stat(:major_gc_count)
        collector.oldmalloc_increase_bytes = GC.stat(:oldmalloc_increase_bytes)
        collector.old_objects = GC.stat(:old_objects)
        collector.allocated_objs = collector.total_allocated_objects
      end

      def self.collector_name
        :gcstats_collector
      end

      attributes :gc_count, :minor_gc_count, :major_gc_count, :allocated_objs, :oldmalloc_increase_bytes, :old_objects, :gc_time

      def enable
        GC.measure_total_time = true unless GC.measure_total_time
        super
      end

      def eden_pages
        GC.stat(:heap_eden_pages)
      end

      def live_slots
        GC.stat(:heap_live_slots)
      end

      def free_slots
        GC.stat(:heap_free_slots)
      end

      def total_allocated_objects
        GC.stat(:total_allocated_objects)
      end

      def count
        GC.count - gc_count
      end

      def time
        # Convert nanoseconds to seconds
        (GC.total_time - gc_time) / 1_000_000_000.0
      end

      def major_count
        GC.stat(:major_gc_count) - major_gc_count
      end

      def minor_count
        GC.stat(:minor_gc_count) - minor_gc_count
      end

      # Object stats since last `reset`.
      #
      # Returns a Number of:
      #   number of allocations since `reset`
      def allocations
        total_allocated_objects - allocated_objs
      end

      def old_object_increase
        GC.stat(:old_objects) - old_objects
      end

      def oldmalloc_increase
        GC.stat(:total_allocated_objects) - oldmalloc_increase_bytes
      end

      # GC stats about the current request.
      #
      # Returns an Array of:
      #   calls - Number of calls to the garbage collection
      #   time  - Time in seconds spent in GC
      #   major - Number of major GCs
      #   minor - Number of minor GCs
      def gc_stats
        [count, time, major_count, minor_count]
      end
    end
  end
end
