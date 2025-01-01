# typed: true
# frozen_string_literal: true

require "resqued/queue_subset_selector"

module GitHub
  module Aqueduct
    module QueueStrategies
      class QueueSubsetSelection

        # Tag key used for tracking queue subset polling
        TAG_QUEUE_SUBSET = "queue_subset"

        # Tag keys for tracking queue ordering and prioritization
        QUEUE_SUBSET_PRIORITIZED = "prioritized"
        QUEUE_SUBSET_SHUFFLED = "shuffled"


        def initialize(queue_subset_selector: nil, prioritize_by: nil)
          @queue_subset_selector = queue_subset_selector || Resqued::QueueSubsetSelector.new
          @queue_subset = {
            QUEUE_SUBSET_PRIORITIZED => {},
            QUEUE_SUBSET_SHUFFLED => {},
          }
          @prioritize_by = prioritize_by
        end

        def apply(queues, tags: {})
          are_queues_prioritized = QueuePrioritization.runtime_queues_prioritized?(tags)

          if use_queue_subset?
            tags[TAG_QUEUE_SUBSET] = "enabled"
            queues = get_queue_subset(queues, are_queues_prioritized)
          else
            tags[TAG_QUEUE_SUBSET] = "disabled"
          end
          queues
        end

        private

        # We use a subset of queues to reduce the number of queues that are polled by each worker
        # As this is an experimental feature, we want to ensure that we can turn it on/off
        # globally and per app-role. This should give us enough flexibility to test it out on high traffic windows.

        def use_queue_subset?
          use_queue_subset_on_all_workers? || use_queue_subset_on_current_approle?
        end

        def use_queue_subset_on_current_approle?
          GitHub.flipper["use_queue_subset_#{GitHub.role}"].enabled?
        end

        def use_queue_subset_on_all_workers?
          GitHub.flipper["use_queue_subset"].enabled?
        end

        def get_queue_subset(queues, is_prioritized)
          subset_queue_kind = is_prioritized ? QUEUE_SUBSET_PRIORITIZED : QUEUE_SUBSET_SHUFFLED
          @queue_subset[subset_queue_kind][queues] ||= @queue_subset_selector.get_subset_from_queues(
            queues,
            prioritize_by: is_prioritized ? @prioritize_by : nil,
          )
        end
      end
    end
  end
end
