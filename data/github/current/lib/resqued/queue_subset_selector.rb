# typed: true
# frozen_string_literal: true

# The `Resqued::QueueSubsetSelector` class is responsible for determining a subset of queues
# from a given list of queues. It can take into account prioritization of queues based on a specified
# criteria and ensures that the subset size adheres to a configurable limit. This is useful
# in scenarios where only a portion of the queues need to be processed or polled at a time,
# either in a prioritized or non-prioritized manner.
module Resqued
  class QueueSubsetSelector
    # Subset size for when we request a subset of queues
    QUEUE_SUBSET_DEFAULT_SIZE = 50

    def initialize(queue_subset_size: QUEUE_SUBSET_DEFAULT_SIZE)
      @queue_subset_size = queue_subset_size
    end

    def get_subset_from_queues(queues, prioritize_by: nil, subset_size: nil)
      # If the queue_subset_size is not set, use the default value
      subset_size ||= @queue_subset_size

      queue_subset = if !prioritize_by.nil?
        # If prioritize_by is set, we need to determine the subset of queues to poll
        determine_proportional_subset(queues, prioritize_by, subset_size)
      else
        # If prioritize_by is not set, we can just take the first subset_size queues
        queues.take(subset_size)
      end

      queue_subset
    end


    private

    def determine_proportional_subset(queues, prioritize_by, subset_size)
      # Group queues into buckets based on prioritization
      buckets = queues.group_by { |queue| prioritize_by.bucket_for(queue) }

      # Calculate the proportional number of queues to select from each bucket
      total_queues = queues.size
      subset = buckets.sort_by { |bucket, _| bucket }.flat_map do |_bucket, bucket_queues|
        bucket_ratio = bucket_queues.size.to_f / total_queues
        bucket_subset_size = (bucket_ratio * subset_size).round
        bucket_queues.take(bucket_subset_size)
      end

      # Ensure the subset size does not exceed the requested size
      subset.take(subset_size)
    end
  end
end
