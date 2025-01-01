# typed: true
# frozen_string_literal: true

require "resqued/queue_subset_selector"
require "github/aqueduct/queue_strategies/queue_prioritization"

module GitHub
  module Aqueduct
    module QueueStrategies
      # QueueSubsetSelection is a strategy that selects a subset of queues based on a queue subset selector.
      #
      # The subset of queues is chosen from the queues returned by the next strategy.
      class QueueSubsetSelection

        # Tag key used for tracking queue subset polling
        TAG_QUEUE_SUBSET = "queue_subset"

        # Default queue subset sizes for dynamic selection
        QUEUE_SUBSET_SIZE_50 = 50
        QUEUE_SUBSET_SIZE_100 = 100
        QUEUE_SUBSET_SIZE_150 = 150
        QUEUE_SUBSET_SIZE_200 = 200

        def initialize(queue_subset_selector: nil, prioritize_by: nil)
          @queue_subset_selector = queue_subset_selector || Resqued::QueueSubsetSelector.new
          @prioritize_by = prioritize_by
        end

        def call(queues, tags, next_strategy)
          queues = next_strategy.call(queues, tags)

          if use_queue_subset?
            tags[TAG_QUEUE_SUBSET] = "enabled"

            # Determine if queues are prioritized
            is_queue_ordering_prioritized = prioritize_queues?
            subset_size = determine_queue_subset_size

            # Build arguments for get_subset_from_queues
            subset_args = {
              prioritize_by: is_queue_ordering_prioritized ? @prioritize_by : nil,
            }
            subset_args[:subset_size] = subset_size if subset_size

            queues = @queue_subset_selector.get_subset_from_queues(queues, **subset_args)

            # Use subset_size if explicitly set by feature flag, otherwise fall back to the selector's default
            actual_subset_size = subset_size || @queue_subset_selector.queue_subset_size
            tags["queue_subset_size"] = actual_subset_size.to_s
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
          FeatureFlag.vexi.enabled?("use_queue_subset_#{GitHub.role}", default: false)
        end

        def use_queue_subset_on_all_workers?
          FeatureFlag.vexi.enabled?("use_queue_subset", default: false)
        end

        # duplicated from QueuePrioritization
        def prioritize_queues?
          FeatureFlag.vexi.enabled?("prioritize_resqued_queues_#{GitHub.role}", default: false)
        end

        # Determine the size of the queue subset based on feature flags
        # This allows for dynamic control of subset size through feature flags
        def determine_queue_subset_size
          # Check for specific subset size feature flags in order of precedence
          if use_queue_subset_size_200?
            QUEUE_SUBSET_SIZE_200
          elsif use_queue_subset_size_150?
            QUEUE_SUBSET_SIZE_150
          elsif use_queue_subset_size_100?
            QUEUE_SUBSET_SIZE_100
          elsif use_queue_subset_size_50?
            QUEUE_SUBSET_SIZE_50
          else
            nil
          end
        end

        ###
        # Queue subset size feature flags
        # - We should have only one of these enabled at a time for a certain app-role
        # - If multiple are enabled, the first one in the if-elsif chain will take precedence
        # - This allows for dynamic control of subset size through feature flags
        # - The feature flags are scoped to the app-role to allow for different subset sizes
        #   across different roles, which is useful for testing and gradual rollouts.
        ###
        def use_queue_subset_size_200?
          FeatureFlag.vexi.enabled?("use_queue_subset_size_200_#{GitHub.role}", default: false)
        end

        def use_queue_subset_size_150?
          FeatureFlag.vexi.enabled?("use_queue_subset_size_150_#{GitHub.role}", default: false)
        end

        def use_queue_subset_size_100?
          FeatureFlag.vexi.enabled?("use_queue_subset_size_100_#{GitHub.role}", default: false)
        end

        def use_queue_subset_size_50?
          FeatureFlag.vexi.enabled?("use_queue_subset_size_50_#{GitHub.role}", default: false)
        end
      end
    end
  end
end
