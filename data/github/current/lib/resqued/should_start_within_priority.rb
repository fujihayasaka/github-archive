# typed: true
# frozen_string_literal: true

#

require_relative "./duration_parser"

module Resqued
  class ShouldStartWithinPriority
    attr_accessor :queue_configurations

    SHOULD_START_WITHIN_PRIORITY = :should_start_within_priority

    SHOULD_START_WITHIN_DEFAULT_VALUE = "1h"

    def initialize(buckets:, queue_configurations: nil)
      @queue_configurations = queue_configurations || BackgroundJobQueues.queue_configurations
      @duration_parser = DurationParser.new
      @buckets = buckets.map(&@duration_parser.method(:get_duration_in_seconds))
    end

    # Performs stable sorting on a list of queues to ensure that the order is deterministic and that the
    # original position is respected when the should_start_within values are equal.
    # Queues will be sorted by bucket queues but not within a queue to respect the fairness of the original order.
    def sort(queues, default_max_delay: SHOULD_START_WITHIN_DEFAULT_VALUE)
      n = 0
      queues.sort_by do |queue|
        n += 1
        should_start_within = should_start_within_for(queue: queue, default_max_delay: default_max_delay)
        [buckets.index { |i| should_start_within <= i } || buckets.length, n]
      end
    end

    private

    attr_reader :buckets

    def should_start_within_for(queue:, default_max_delay: SHOULD_START_WITHIN_DEFAULT_VALUE)
      @queue_configurations.dig(queue, :scheduling_hints, :should_start_within_secs) ||
      @duration_parser.get_duration_in_seconds(default_max_delay)
    end
  end
end
