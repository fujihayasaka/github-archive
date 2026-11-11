# typed: true
# frozen_string_literal: true

module Platform
  module Directives
    # Modify the library's `@stream` implementation to work with GraphQL-Batch
    class Stream < GraphQL::Pro::Stream
      def self.resolve_each(obj, arguments, context, &block)
        # only use defer if the run_defer_directive flag is set on the context
        if context[:run_defer_directive]
          # While the query is running, store the batch executor to re-use later
          context[:graphql_batch_executor] ||= GraphQL::Batch::Executor.current

          # Override the parent implementation to use our custom Deferral class.
          # The parent class (GraphQL::Pro::Stream) hardcodes Pro::Defer::Deferral,
          # which doesn't have our GraphQL-Batch integration or optimization flags.
          #
          # The context[:batch_deferred_chunks] flag is set at the entry point
          # to enable batching for specific controllers/actions.
          if arguments[:if] && context[:batch_deferred_chunks]
            initial_count = arguments[:initial_count]
            path = context[:current_path]
            if path.last < initial_count
              yield
            else
              defer = context[:defer] ||= GraphQL::Pro::Defer::Deferred.new(context)
              defer.deferrals << Platform::Directives::Defer::Deferral.new(
                block: block,
                path: path,
                context: context,
                label: arguments[:label],
              )
            end
          else
            super
          end
        else
          yield
        end
      end

      def self.visible?(context)
        return context[:mask].target == :internal if context[:mask].present?
        context[:target] == :internal
      end
    end
  end
end
