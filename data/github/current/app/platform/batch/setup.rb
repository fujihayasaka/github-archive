# typed: true
# frozen_string_literal: true
module Platform
  module Batch
    class Setup < GraphQL::Batch::SetupMultiplex
      REQUEST_EXECUTOR_KEY = :GRAPHQL_BATCH_REQUEST_EXECUTOR

      def before_multiplex(_)
        # here we may have already an executor, being used for the current request
        # We save it in a thread local variable, and we'll reset it when we're done
        # batching the graphql request
        existing = GraphQL::Batch::Executor.current
        Thread.current[REQUEST_EXECUTOR_KEY] = existing
        GraphQL::Batch::Executor.current = nil
        super
      end

      def after_multiplex(_)
        super
        # Set the GraphQL Batch Executor to what is was
        # before the graphql query started
        existing = Thread.current[REQUEST_EXECUTOR_KEY]
        GraphQL::Batch::Executor.current = existing
      end

      module Trace
        def initialize(executor_class: Platform::Batch::GraphqlExecutor, **_rest)
          @executor_class = executor_class
          super
        end

        def execute_multiplex(multiplex:)
          existing = GraphQL::Batch::Executor.current
          Thread.current[REQUEST_EXECUTOR_KEY] = existing
          GraphQL::Batch::Executor.current = nil
          GraphQL::Batch::Executor.start_batch(@executor_class)
          super
        ensure
          GraphQL::Batch::Executor.end_batch
          # Set the GraphQL Batch Executor to what is was
          # before the graphql query started
          existing = Thread.current[REQUEST_EXECUTOR_KEY]
          GraphQL::Batch::Executor.current = existing
        end
      end
    end
  end
end
