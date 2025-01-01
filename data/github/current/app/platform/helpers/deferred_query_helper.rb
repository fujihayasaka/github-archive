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
# - `execute_deferral_chunk(query, deferred)`: This method executes a single deferred query chunk.
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
      extend T::Sig

      sig { params(hash: T::Hash[String, T.untyped], chunk: T::Hash[T.untyped, T.untyped]).void }
      def add_chunks_to_hash(hash, chunk)
        current_object = T.let(hash, T.untyped)

        # get the path until the last key
        (*paths, key) = chunk[:path]

        # get the reference of the nested hash
        current_object = current_object.dig(*paths) if paths.size > 0

        # set the value
        current_object[key] = chunk[:data] if current_object
      end

      sig { params(query: GraphQL::Query, deferred: T.untyped).returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
      def execute_deferral_chunk(query, deferred)
        tags = get_tags(query.context)
        tags << "chunk_label:#{deferred.label}" if deferred.label.present? && deferred.label.size > 0

        # TODO: look into wrapping this with
        # - GitHub.tracer.in_span

        # Creating a new query tracker for the deferred chunk execution
        deferred_tracker = Platform::QueryTracker.new(query, query_hash: query.context[:query_tracker].query_hash, execution_type: "deferred_chunk", defer_label: deferred.label)

        result = T.let(nil, T.untyped)

        deferred_tracker.track do
          begin
            GitHub.dogstats.distribution_time("platform.chunk.run", tags: tags) do
              ActiveRecord::Base.connected_to(role: :reading) do
                Platform::Security::RepositoryAccess.with_viewer(query.context[:viewer]) do
                  result = deferred.to_h
                  # incase a deferred chunk has an error we null out the field and the client can decide what to do with it
                  # either not render or raise
                  # a potential follow up would be to return the error message to the client to provide more context
                  # this is tracked in this issue: https://github.com/github/issues/issues/11212
                  if result[:errors].present?
                    Platform.instrument_errors!(query)
                  end
                  result
                end
              end
            end
          rescue => exception # rubocop:todo Lint/GenericRescue
            # log to sentry and datadog
            is_development = Rails.env && Rails.env.development?
            unless query.context[:error_reported]
              query_name = query.context[:query_name]
              Platform.instrument_internal_errors(query:, query_name:)
              Platform.report_internal_errors!(
                exception:,
                report_exceptions_to_failbot:  T.must(!is_development),
                query:,
                query_name:
              )
            end
            query.context[:internal_error] = exception
            nil
          end
        end
        query.context[:query_tracker].add_deferred_fragment_tracker(deferred_tracker)
        result
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
          GitHub.dogstats.distribution_time("platform.defer.run", tags: tags) do
            chunk_index = 0
            gql_query_object.context[:defer].each do |deferred|
              # the first chunk is already in the query result
              if chunk_index > 0
                chunk = execute_deferral_chunk(gql_query_object, deferred)
                add_chunks_to_hash(initial_data, chunk) if chunk.present?
              end
              chunk_index += 1
            end
          end
        end
      end
    end
  end
end
