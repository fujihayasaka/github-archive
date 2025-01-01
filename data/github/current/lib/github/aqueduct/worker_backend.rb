# typed: true
# frozen_string_literal: true

require "forwardable"
require "resqued/queue_subset_selector"

module GitHub
  module Aqueduct
    class WorkerBackend
      extend Forwardable

      attr_reader :backend, :queue_strategies

      # Delegate all methods except pop to @backend
      T.unsafe(self).def_delegators :@backend, *(::Aqueduct::Worker::Backend.instance_methods(false) - [:pop])

      def initialize(backend:, queue_strategies: [])
        @backend = backend
        @queue_strategies = queue_strategies
        @base_tags = GitHub.aqueduct_tags
      end

      def pop(queues, timeout, tags: {}, worker_id:, worker_pool: nil, worker_idle_ms: 0)
        # We calculate the runtime tags to emit per pop
        runtime_tags = @base_tags.merge(tags)

        # We apply all the queue strategies in the order they are defined.
        # - ArgTags are passed to the strategies to allow them to add additional metrics. The arg is optional but if not passed, we will not be able to populate the metrics.
        queues = apply_queue_strategies(queues, tags: tags)

        before_pop
        job = @backend.pop(queues, timeout, tags: tags, worker_id: worker_id, worker_pool: worker_pool, worker_idle_ms: worker_idle_ms)
        GitHub.dogstats.count("job.backend.pop", 1, tags: runtime_tags)
        after_pop

        job
      end

      def before_pop
      end

      def after_pop
      end

      private

      def apply_queue_strategies(queues, tags: {})
        @queue_strategies.reduce(queues) do |current_queues, strategy|
          strategy.apply(current_queues, tags: tags)
        end
      end
    end
  end
end
