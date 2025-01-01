# typed: true
# frozen_string_literal: true

module Platform
  module Directives
    # Modify the library's `@defer` implementation to work with GraphQL-Batch
    class Defer < GraphQL::Pro::Defer
      def self.resolve(obj, arguments, context, &block)
        # only use defer if the run_defer_directive flag is set on the context
        if context[:run_defer_directive]
          # While the query is running, store the batch executor to re-use later
          context[:graphql_batch_executor] ||= GraphQL::Batch::Executor.current
          super
        else
          yield
        end
      end

      def self.visible?(context)
        return context[:mask].target == :internal if context[:mask].present?
        context[:target] == :internal
      end

      class Deferral < GraphQL::Pro::Defer::Deferral
        def resolve
          # Before calling the deferred execution,
          # set GraphQL-Batch back up:
          prev_executor = GraphQL::Batch::Executor.current
          GraphQL::Batch::Executor.current ||= @context[:graphql_batch_executor]
          super
        ensure
          # Clean up afterward:
          GraphQL::Batch::Executor.current = prev_executor
        end
      end
    end
  end
end
