# typed: true
# frozen_string_literal: true

module Platform
  module Tracing
    module DbTracer
      include Kernel

      # Database call limits for all queries
      MAX_DB_CALLS = GitHub::Config::RequestLimits::GRAPHQL_DATABASE_BUDGET_MAX
      # Database call limits for exempted mutations approved by GraphQL Platform team only
      MAX_DB_CALLS_EXEMPTED_MUTATIONS = GitHub::Config::RequestLimits::GRAPHQL_DATABASE_BUDGET_MAX_EXEMPTED_MUTATIONS

      EXEMPT_MUTATIONS = [
        Platform::Mutations::CreateEnterpriseOrganization,
        Platform::Mutations::ApproveActionRequiredWorkflowRuns,
      ].freeze

      # This is called in the _initial_ resolve call, before any promises are returned.
      def execute_field(field:, query:, ast_node:, arguments:, object:)
        memoize_exempted_mutation(query: query, field: field)
        enforce_db_call_limit_and_execute(query: query) { super }
      end

      # This is called in the lazy execution phase, after promises are returned.
      def execute_field_lazy(field:, query:, ast_node:, arguments:, object:)
        memoize_exempted_mutation(query: query, field: field)
        enforce_db_call_limit_and_execute(query: query) { super }
      end

      private

      # Memoize once per request whether the operation is a exempted mutation.
      def memoize_exempted_mutation(query:, field:)
        return false unless query.mutation?

        context = query.context
        return if context.key?(:db_hard_limit_exempted_mutation) # already memoized

        exempted = false

        mutation_class = field&.mutation || field&.resolver
        exempted ||= mutation_class && EXEMPT_MUTATIONS.include?(mutation_class)

        context[:db_hard_limit_exempted_mutation] = exempted
      rescue => e
        # Be resilient: never block execution if we can’t derive
        Failbot.report(e, "code.namespace": "Platform::Tracing::DbTracer", "code.function": "memoize_exempted_mutation")
        context[:db_hard_limit_exempted_mutation] = false
      end

      def enforce_db_call_limit_and_execute(query:)
        context = query.context

        # The database hard limit is not applicable to GHES
        return yield if GitHub.enterprise?

        # Skip for persisted queries or if the query itself is internal
        is_persisted_query = context[:operation_id].present?
        is_internal_query = context[:target] == :internal
        return yield if is_persisted_query || is_internal_query

        query_tracker = context[:query_tracker]
        # Allow field execution to proceed if no query tracker is available
        return yield if query_tracker.nil?

        db_count = query_tracker.mysql_count
        limit = context[:db_hard_limit_exempted_mutation] ? MAX_DB_CALLS_EXEMPTED_MUTATIONS : MAX_DB_CALLS

        # Allow field execution as normal if db_count is below the maximum allowed
        return yield unless db_count > limit

        GitHub.dogstats.increment("platform.query.db_calls_exceeded")
        raise Platform::Errors::ResourceLimitsExceeded.new
      end
    end
  end
end
