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
        elsif current_object[key] && current_object[key].is_a?(Hash)
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

      sig { params(gql_query_object: GraphQL::Query, initial_data: T::Hash[String, T.untyped]).void }
      def execute_deferral_for_query(gql_query_object, initial_data)
        if gql_query_object.context[:defer].present?
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
        end
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
            rescue => exception # rubocop:todo Lint/GenericRescue
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
    end
  end
end
