# typed: true
# frozen_string_literal: true

require "forwardable"

module GitHub
  module Aqueduct
    # QueueStrategyBackend wraps an Aqueduct::Worker::Backend and applies
    # configurable queue strategies to every `pop` call to limit, reorder, or
    # filter the list of queues. Strategies work like middleware.
    class QueueStrategyBackend
      extend Forwardable

      attr_reader :backend, :queue_strategies

      # Delegate all methods except pop to @backend
      T.unsafe(self).def_delegators :@backend, *(::Aqueduct::Worker::Backend.instance_methods(false) - [:pop])

      def initialize(backend:, queue_strategies: [])
        @backend = backend
        @base_tags = GitHub.aqueduct_tags

        # Build a middleware stack of strategies, using wrapping lambdas.
        # The bottom of the stack just returns the queues as given. The first
        # strategy in the list is called first, and each strategy in turn
        # decides whether to return a value immediately or invoke the next
        # strategy in the stack.
        stack = ->(q, _t) { q }
        queue_strategies.reverse_each do |strategy|
          current_stack = stack
          stack = ->(q, t) { strategy.call(q, t, current_stack) }
        end
        @stack = stack
      end

      def pop(queues, timeout, tags: {}, worker_id:, worker_pool: nil, worker_idle_ms: 0)
        runtime_tags = @base_tags.merge(tags)

        queues = @stack.call(queues, runtime_tags)

        job = @backend.pop(queues, timeout, tags: runtime_tags, worker_id: worker_id, worker_pool: worker_pool, worker_idle_ms: worker_idle_ms)
        GitHub.dogstats.count("job.backend.pop", 1, tags: runtime_tags)

        job
      end
    end
  end
end
