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
        attr_reader :deferred_result, :block_executed
        attr_accessor :synced_result

        def resolve
          # Before calling the deferred execution,
          # set GraphQL-Batch back up:
          prev_executor = GraphQL::Batch::Executor.current
          GraphQL::Batch::Executor.current ||= @context[:graphql_batch_executor]

          # With the optimization flag, bypass the parent's run_isolated to allow
          # batching across multiple deferred chunks. Without this, each deferred
          # chunk creates an isolated dataloader run, causing N+1 queries.
          #
          # The context[:batch_deferred_chunks] flag is set at the entry point
          # to enable batching for specific controllers/actions.
          if @context[:batch_deferred_chunks]
            resolve_without_isolation
          else
            super
          end
        ensure
          # Clean up afterward:
          GraphQL::Batch::Executor.current = prev_executor
        end

        # Execute the block but DON'T sync lazies yet.
        # This allows multiple deferrals to queue up their loader requests.
        def execute_block_only
          return if @block_executed
          @block_executed = true
          @deferred_result = @block.call
        end

        def set_synced_result(result)
          @synced_result = result
        end

        # Finish resolution using the pre-synced result.
        # This skips the sync_lazy call since it was already done externally.
        def finish_with_synced_result
          return if @was_resolved
          @was_resolved = true
          finalize_result_data(@synced_result)
        end

        # Finish resolution by syncing lazies and collecting results.
        # Should be called AFTER all deferrals have executed their blocks.
        def finish_resolution
          resolve_without_isolation(deferred_result: @deferred_result)
        end

        # Override the to_h method to include BOTH data and errors (if any)
        def to_h
          result = super
          result[:data] = self.data

          result
        end

        private

        # Resolve without dataloader isolation, allowing multiple deferred chunks
        # to share the same dataloader context and batch loader requests together.
        def resolve_without_isolation(deferred_result: nil)
          return if @was_resolved
          @was_resolved = true

          # Execute the deferred block (unless already executed)
          deferred_result ||= @block.call

          # Sync lazy values without isolation to enable batching across chunks
          deferred_result = @context.schema.sync_lazy(deferred_result)
          GraphQL::Execution::Interpreter::Resolve.resolve_all([deferred_result], @context.dataloader)

          finalize_result_data(deferred_result)
        end

        # Shared finalization logic for storing result data and collecting errors.
        # Handles unwrapping GraphQL-Ruby response objects and error tracking.
        def finalize_result_data(result)
          prev_error_count = @context.errors.size

          # GraphQL-Ruby wraps results in response objects in some versions.
          # We need to unwrap to get the raw data. This is defensive code
          # to handle different GraphQL-Ruby versions.
          if result.respond_to?(:graphql_result_data)
            result = result.graphql_result_data
          end

          # Dup the value because, if it has nested patches,
          # they'll be added later to the same hash.
          @data = isolate_copy(result)

          new_error_count = @context.errors.size
          if new_error_count > prev_error_count
            own_errors = @context.errors.last(new_error_count - prev_error_count)
            own_errors.each { |e| e.respond_to?(:path=) && e.path.nil? && e.path = @path }
            @errors = own_errors.map(&:to_h)
          end
        end
      end
    end
  end
end
