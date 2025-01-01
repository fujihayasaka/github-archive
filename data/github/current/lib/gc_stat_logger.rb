# typed: false
# frozen_string_literal: true

# GCStatLogger – Send Ruby GC stats to Datadog
#
# This class will send GC stats to datadog at a given stat prefix and sample rate.
#
# Usage:
#
#    class GCStatMiddware
#      GCStats = GCStatLogger.new("request", sample_rate: 0.2)
#
#      def do_request(env)
#        GCStats.track_ruby_gc(tags: ["server-type:unicorn"]) do
#          @rack.call(env)
#        end
#      end
#    end
#
# Stats:
#   The following stats are sent to datadog, with the stat_prefix prepending it:
#
#     1. gc.allocations     – gauge of object count allocated during the block
#     1. gc.eden_pages      – gauge of total eden pages
#     1. gc.live_slots      – gauge of total live slots on the heap
#     1. gc.heap_free_slots – gauge of total free slots on the heap
#     1. gc.count           – gauge of major and minor GC's during the block (differentiated by 'level' tag value)
#     1. gc.time.real       – real CPU time used during the block's execution
#     1. gc.time.cpu        – CPU time used during the block's execution
#     1. gc.time.idle       – time difference between real CPU time and CPU time
#
class GCStatLogger
  attr_reader :stat_prefix, :sample_rate

  # Create a new GCStatLogger
  #
  # stat_prefix - prefix for your Datadog stat (not including the .)
  # sample_rate - float representing proportion (0, 1] of stats to generate and send out
  def initialize(stat_prefix:, sample_rate: 1)
    @stat_prefix = stat_prefix
    @sample_rate = sample_rate
  end

  # Track Ruby GC statistics as described in the class documentation.
  #
  # tags  - an array of tags to send along with the stats
  # block - code to measure
  #
  # Returns nothing.
  def track_ruby_gc(tags:, &block)
    allocations_so_far = GC.stat(:total_allocated_objects)
    major_gc_so_far    = GC.stat(:major_gc_count)
    minor_gc_so_far    = GC.stat(:minor_gc_count)
    start_time_real    = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    start_time_cpu     = Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID)
    block.call
  ensure
    allocations = GC.stat(:total_allocated_objects) - allocations_so_far
    minor_count = GC.stat(:minor_gc_count) - minor_gc_so_far
    major_count = GC.stat(:major_gc_count) - major_gc_so_far
    time_real   = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time_real
    time_cpu    = Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID) - start_time_cpu
    time_idle   = time_real - time_cpu

    dogstats = GitHub.dogstats
    dogstats.gauge  "#{stat_prefix}.gc.allocations",     allocations, tags: tags, sample_rate: sample_rate
    dogstats.gauge  "#{stat_prefix}.gc.eden_pages",      GC.stat(:heap_eden_pages), tags: tags, sample_rate: sample_rate
    dogstats.gauge  "#{stat_prefix}.gc.live_slots",      GC.stat(:heap_live_slots), tags: tags, sample_rate: sample_rate
    dogstats.gauge  "#{stat_prefix}.gc.heap_free_slots", GC.stat(:heap_free_slots), tags: tags, sample_rate: sample_rate
    dogstats.gauge  "#{stat_prefix}.gc.count",           minor_count, tags: tags + ["level:minor"], sample_rate: sample_rate
    dogstats.gauge  "#{stat_prefix}.gc.count",           major_count, tags: tags + ["level:major"], sample_rate: sample_rate
    dogstats.timing "#{stat_prefix}.time.real",          time_real * 1000, tags: tags, sample_rate: sample_rate
    dogstats.timing "#{stat_prefix}.time.cpu",           time_cpu * 1000, tags: tags, sample_rate: sample_rate
    dogstats.timing "#{stat_prefix}.time.idle",          time_idle * 1000, tags: tags, sample_rate: sample_rate
  end
end
