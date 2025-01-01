# typed: true
# frozen_string_literal: true

module GitHub
  module Aqueduct
    module QueueStrategies
      # QueuePrioritization is a strategy that prioritizes queues based on a given prioritization method.
      #
      # Prioritization is applied to the queues returned by the next strategy.
      class QueuePrioritization

        TAG_QUEUE_ORDERING = "queue_ordering"
        QUEUE_ORDERING_PRIORITIZED = "prioritized"
        QUEUE_ORDERING_SHUFFLED = "resqued_shuffled"

        def initialize(prioritize_by: nil)
          @prioritize_by = prioritize_by
        end

        def call(queues, tags, next_strategy)
          queues = next_strategy.call(queues, tags)

          if @prioritize_by && prioritize_queues?
            tags[TAG_QUEUE_ORDERING] = QUEUE_ORDERING_PRIORITIZED
            queues = @prioritize_by.sort(queues)
          else
            tags[TAG_QUEUE_ORDERING] = QUEUE_ORDERING_SHUFFLED
          end

          queues
        end

        private

        def prioritize_queues?
          FeatureFlag.vexi.enabled?("prioritize_resqued_queues_#{GitHub.role}", default: false)
        end
      end
    end
  end
end
