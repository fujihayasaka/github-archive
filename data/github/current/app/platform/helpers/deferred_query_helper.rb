# typed: true
# frozen_string_literal: true

# The DeferredQueryHelper module is a part of the Platform::Helpers module.
# It provides methods to handle deferred queries in a GraphQL context.
# Deferred queries allow parts of a GraphQL query to be executed at a later time,
# which can be useful for performance reasons.
#
# The main responsibilities of this module are:
#
# - `add_chunks_to_hash(hash, chunk)`: This method adds chunks of data to a given hash.
#   It's used to add the result of a deferred query to the overall result.
#
# - `execute_deferred_chunks(gql_query_object, initial_data, chunks, label, execution_type)`: This method
#   executes a batch of deferred query chunks.
#   It also handles errors that might occur during the execution of the deferred query.
#
# - `get_tags(context)`: This method extracts tags from the query context. These tags are used for
#   monitoring and performance tracking purposes.
#
# - `execute_deferral_for_query(gql_query_object, initial_data)`: This method executes all deferred
#   queries for a given GraphQL query object. It uses the other methods in this module to execute
#   each deferred query and add its result to the overall result.
module Platform
  module Helpers
    module DeferredQueryHelper
      sig { params(hash: T::Hash[String, T.untyped], chunk: T::Hash[T.untyped, T.untyped]).void }
      def add_chunks_to_hash(hash, chunk)
        current_object = T.let(hash, T.untyped)

        # get the path until the last key
        (*paths, key) = chunk[:path]

        # get the reference of the nested hash
        current_object = current_object.dig(*paths) if paths.size > 0

        return unless current_object

        # set the value
        if current_object[key] && current_object[key].is_a?(Array)
          current_object[key] << chunk[:data]
        elsif current_object[key] && current_object[key].is_a?(Hash) && chunk[:data].is_a?(Hash)
          current_object[key] = current_object[key].merge(chunk[:data])
        else
          current_object[key] = chunk[:data]
        end
      end

      def get_tags(context)
        tags = T.let([], T::Array[String])
        tags << "query_owning_catalog_service:#{context[:query_owning_catalog_service]}" if context[:query_owning_catalog_service]
        tags << "operation_name:#{context[:query_name]}" if context[:query_name]
        tags += context[:reporting_tags] if context[:reporting_tags]
        tags
      end

      sig { params(gql_query_object: GraphQL::Query, initial_data: T.nilable(T::Hash[String, T.untyped])).returns(T::Hash[String, T.untyped]) }
      def execute_deferral_for_query(gql_query_object, initial_data)
        return {} if initial_data.nil?

        if gql_query_object.context[:defer].present?
          begin
            tags = get_tags(gql_query_object.context)
            deferred_fragments = []
            streamed_connections = Hash.new

            tracer_attributes = {
              "gh.graphql.query_hash" => gql_query_object.context[:query_tracker].query_hash,
              "gh.graphql.variables_hash" => gql_query_object.context[:query_tracker].variables_hash,
            }
            tracer_attributes["gh.graphql.query_name"] = gql_query_object.context[:query_name] if gql_query_object.context[:query_name].present?

            GitHub.tracer.in_span("platform.defer.execute", attributes: tracer_attributes, kind: :internal) do
              GitHub.dogstats.distribution_time("platform.defer.run", tags: tags) do
                # Check if batch optimization is enabled for this query.
                # The context flag is set at the entry point for specific controllers/actions.
                batch_enabled = gql_query_object.context[:batch_deferred_chunks]

                chunk_index = 0
                gql_query_object.context[:defer].each do |deferred|
                  # the first (main) chunk is already in the query result
                  if chunk_index > 0
                    if deferred.label.present? && deferred.label.size > 0
                      # the label for stream connections is in the format of `<FRAGMENT_NAME>$stream$<STREAM_KEY>`
                      # it will also contain a chunk with the label `<FRAGMENT_NAME>$defer$<STREAM_KEY>$pageInfo`
                      stream_label = deferred.label.match(/\A(.*?)\$(?:stream|defer)\$([^$]+)/)
                    end
                    # a deferred chunk belongs either to a deferred fragment or to a stream connection
                    if stream_label
                      # chunks belonging to a stream connection are grouped by the stream key
                      streamed_connections[stream_label[1]] ||= []
                      streamed_connections[stream_label[1]] << deferred
                    elsif batch_enabled && deferred.label.present?
                      # When batch optimization is enabled, group all labeled deferrals together
                      # to enable loader batching across chunks
                      streamed_connections[deferred.label] ||= []
                      streamed_connections[deferred.label] << deferred
                    else
                      # we assume a one-to-one relationship between deferred fragments and deferred chunks
                      deferred_fragments << deferred
                    end
                  end
                  chunk_index += 1
                end

                execute_deferral_for_deferred_fragments(gql_query_object, initial_data, deferred_fragments)
                execute_deferral_for_streamed_connections(gql_query_object, initial_data, streamed_connections)
              end
            end
          ensure
            # Resolving deferred fragments / streamed connections re-enters the GraphQL
            # interpreter runtime (via `deferred.to_h`), which repopulates the fiber-local
            # `Fiber[:__graphql_runtime_info]` hash with this query's runtime state.
            # graphql-ruby only clears that entry inside `Interpreter.run_all`'s ensure
            # block, which already ran during the initial (non-deferred) execution pass.
            # Without clearing it again here, every deferred query is retained for the life
            # of the process, leaking its entire execution graph (AST, QueryTracker, resolved
            # records, perf-tracer timings). See github/monolith-systems#928.
            clear_interpreter_runtime_state(gql_query_object)
          end
        end

        initial_data
      end

      sig { params(gql_query_object: GraphQL::Query, initial_data: T::Hash[String, T.untyped], deferred_fragments: T::Array[Platform::Directives::Defer::Deferral]).void }
      def execute_deferral_for_deferred_fragments(gql_query_object, initial_data, deferred_fragments)
        return if deferred_fragments.empty?

        deferred_fragments.each do |deferred|
          execute_deferred_chunks(gql_query_object, initial_data, [deferred], deferred.label, "deferred_chunk")
        end
      end

      sig { params(gql_query_object: GraphQL::Query, initial_data: T::Hash[String, T.untyped], streamed_connections: T::Hash[String, T::Array[Platform::Directives::Defer::Deferral]]).void }
      def execute_deferral_for_streamed_connections(gql_query_object, initial_data, streamed_connections)
        return if streamed_connections.empty?

        streamed_connections.each do |label, deferred_chunks|
          execute_deferred_chunks(gql_query_object, initial_data, deferred_chunks, label, "streamed_chunks")
        end
      end

      sig { params(gql_query_object: GraphQL::Query, initial_data: T::Hash[String, T.untyped], chunks: T::Array[Platform::Directives::Defer::Deferral], label: T.nilable(String), execution_type: String).void }
      def execute_deferred_chunks(gql_query_object, initial_data, chunks, label, execution_type)
        tags = get_tags(gql_query_object.context)
        tags << "chunk_label:#{label}" if label.present? && label.size > 0

        deferred_tracker = Platform::QueryTracker.new(gql_query_object, query_hash: gql_query_object.context[:query_tracker].query_hash, execution_type: execution_type, defer_label: label)

        deferred_tracker.track do
          tracer_attributes = {
            "gh.graphql.query_hash" => gql_query_object.context[:query_tracker].query_hash,
            "gh.graphql.variables_hash" => gql_query_object.context[:query_tracker].variables_hash,
            "gh.graphql.deferred_chunk.execution_type" => execution_type,
          }
          tracer_attributes["gh.graphql.query_name"] = gql_query_object.context[:query_name] if gql_query_object.context[:query_name].present?
          tracer_attributes["gh.graphql.deferred_chunk.label"] = label if label.present?

          GitHub.tracer.in_span("platform.defer.chunk.run", attributes: tracer_attributes, kind: :internal) do |span|
            begin
              GitHub.dogstats.distribution_time("platform.chunk.run", tags: tags) do
                ActiveRecord::Base.connected_to(role: :reading) do
                  Platform::Security::RepositoryAccess.with_viewer(gql_query_object.context[:viewer]) do
                    # Optimization: Batch-process all chunks together to enable loader batching.
                    # Without this, each deferred.to_h triggers an isolated resolution,
                    # causing N+1 queries as each chunk's loaders resolve separately.
                    #
                    # The context[:batch_deferred_chunks] flag is set at the entry point
                    # to enable batching for specific controllers/actions.
                    batch_enabled = gql_query_object.context[:batch_deferred_chunks]
                    if batch_enabled && chunks.size > 1
                      resolve_chunks_batched(chunks, initial_data, gql_query_object)
                    else
                      chunks.each do |deferred|
                        chunk = deferred.to_h

                        if chunk[:errors].present?
                          Platform.instrument_errors!(gql_query_object)
                        end

                        add_chunks_to_hash(initial_data, chunk) if chunk.present?
                      end
                    end
                  end
                end
              end
            rescue => exception
              # log to sentry and datadog
              is_development = Rails.env && Rails.env.development?
              unless gql_query_object.context[:error_reported]
                query_name = gql_query_object.context[:query_name]
                Platform.instrument_internal_errors(
                  query: gql_query_object,
                  query_name:,
                  exception:,
                )
                Platform.report_internal_errors!(
                  exception:,
                  report_exceptions_to_failbot:  T.must(!is_development),
                  query: gql_query_object,
                  query_name:
                )
              end
              span.record_exception(exception)
              gql_query_object.context[:internal_error] = exception
            end
          end
        end

        deferred_tracker.set_streamed_chunks_count(chunks.size) if execution_type == "streamed_chunks"
        gql_query_object.context[:query_tracker].add_deferred_fragment_tracker(deferred_tracker)
      end

      private

      # Removes this query's runtime state from graphql-ruby's fiber-local
      # `Fiber[:__graphql_runtime_info]` hash after deferred execution completes.
      #
      # Deferred fragments and streamed connections are resolved by re-entering the
      # interpreter runtime, which lazily recreates `Fiber[:__graphql_runtime_info][query]`.
      # graphql-ruby only clears that hash inside `Interpreter.run_all`'s ensure block
      # (the initial, non-deferred pass), so without this cleanup the query — and the
      # entire object graph it references — is retained for the life of the process.
      #
      # This mirrors what the gem itself does, calling the same public
      # `Runtime#delete_all_interpreter_context` used in `Interpreter.run_all`.
      sig { params(gql_query_object: GraphQL::Query).void }
      def clear_interpreter_runtime_state(gql_query_object)
        runtime = gql_query_object.context.namespace(:interpreter_runtime)[:runtime]
        runtime&.delete_all_interpreter_context
      end

      # Resolves multiple deferred chunks together with batched loader execution.
      # This enables loader batching across chunks, reducing N+1 queries.
      #
      # Phase 1: Execute all deferred blocks (queues up loader requests)
      # Phase 2: Run the dataloader to batch-resolve all pending requests
      # Phase 3: Finish resolution and collect results
      sig { params(chunks: T::Array[T.untyped], initial_data: T::Hash[String, T.untyped], gql_query_object: GraphQL::Query).void }
      def resolve_chunks_batched(chunks, initial_data, gql_query_object)
        # Set up the shared GraphQL-Batch executor for all chunks
        prev_executor = GraphQL::Batch::Executor.current
        GraphQL::Batch::Executor.current ||= gql_query_object.context[:graphql_batch_executor]

        begin
          # Split chunks into those that support batched resolution and those that don't
          # (e.g., @stream chunks support execute_block_only, but @defer pageInfo chunks may not)
          batchable_chunks = chunks.select { |c| c.respond_to?(:execute_block_only) }
          non_batchable_chunks = chunks.reject { |c| c.respond_to?(:execute_block_only) }

          # Process batchable chunks together for loader batching
          if batchable_chunks.size > 1
            # Phase 1: Execute all blocks - this queues up loader requests
            batchable_chunks.each(&:execute_block_only)

            # Phase 2: Sync all lazy values together, then run dataloader once
            # This is the key to batching - we need to resolve ALL lazies together
            schema = gql_query_object.context.schema
            dataloader = gql_query_object.context.dataloader
            all_lazy_results = batchable_chunks.map(&:deferred_result)

            # Sync all lazies together and update each chunk's deferred_result
            batchable_chunks.each_with_index do |deferred, idx|
              synced = schema.sync_lazy(all_lazy_results[idx])
              deferred.set_synced_result(synced)
            end

            # Run resolve_all on all synced results to resolve any nested lazies
            all_synced = batchable_chunks.map(&:synced_result)
            GraphQL::Execution::Interpreter::Resolve.resolve_all(all_synced, dataloader)

            # Run the dataloader to execute any pending requests
            dataloader.run if dataloader&.respond_to?(:run)

            # Phase 3: Finish resolution and collect results for each chunk
            batchable_chunks.each do |deferred|
              deferred.finish_with_synced_result
              chunk = deferred.to_h
              if chunk[:errors].present?
                Platform.instrument_errors!(gql_query_object)
              end
              add_chunks_to_hash(initial_data, chunk) if chunk.present?
            end

            # Log success metrics for batched resolution
            tags = get_tags(gql_query_object.context)
            GitHub.dogstats.increment("platform.defer.batch_resolution.success", tags: tags)
            GitHub.dogstats.histogram("platform.defer.batch_resolution.chunk_count", batchable_chunks.size, tags: tags)
          elsif batchable_chunks.size == 1
            # Single batchable chunk - just resolve normally
            deferred = batchable_chunks.first
            chunk = deferred.to_h
            if chunk[:errors].present?
              Platform.instrument_errors!(gql_query_object)
            end
            add_chunks_to_hash(initial_data, chunk) if chunk.present?
          end

          # Process non-batchable chunks individually (e.g., pageInfo)
          non_batchable_chunks.each do |deferred|
            chunk = deferred.to_h
            if chunk[:errors].present?
              Platform.instrument_errors!(gql_query_object)
            end
            add_chunks_to_hash(initial_data, chunk) if chunk.present?
          end
        ensure
          GraphQL::Batch::Executor.current = prev_executor
        end
      end
    end
  end
end
