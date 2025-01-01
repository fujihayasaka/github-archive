# typed: true
# frozen_string_literal: true

module GitHub
  module Aqueduct
    module QueueStrategies
      class QueuePrioritization

        TAG_QUEUE_ORDERING = "queue_ordering"
        QUEUE_ORDERING_PRIORITIZED = "prioritized"
        QUEUE_ORDERING_SHUFFLED = "resqued_shuffled"

        def initialize(prioritize_by: nil)
          @prioritize_by = prioritize_by
          @prioritized_queues = {}
        end

        def apply(queues, tags: {})
          is_queue_ordering_prioritized = @prioritize_by && prioritize_queues?

          if is_queue_ordering_prioritized
            tags[TAG_QUEUE_ORDERING] = QUEUE_ORDERING_PRIORITIZED
            queues = prioritize_queues(queues)
          else
            tags[TAG_QUEUE_ORDERING] = QUEUE_ORDERING_SHUFFLED
          end

          queues
        end

        def self.runtime_queues_prioritized?(tags)
          tags[TAG_QUEUE_ORDERING] == QUEUE_ORDERING_PRIORITIZED
        end

        private

        def prioritize_queues?
          GitHub.flipper["prioritize_resqued_queues_#{GitHub.role}"].enabled?
        end

        def prioritize_queues(queues)
          return queues unless @prioritize_by
          @prioritized_queues[queues] ||= @prioritize_by.sort(queues)
        end
      end
    end
  end
end
